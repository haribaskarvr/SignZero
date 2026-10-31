/**
 * Flow / Apex entry point. Creates an envelope for a PDF in Salesforce Files and invites the first
 * routing order. The caller's access is enforced on the way in (create permission on envelopes, and the
 * file is read in user mode); the envelope records themselves are written in system mode because their
 * hash and status fields are read-only for people.
 */
public with sharing class SignZeroOrchestrator {
  private static final Pattern EMAIL = Pattern.compile(
    '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
  );

  /** One envelope to send, as the invocable action's input. */
  public class DispatchRequest {
    @InvocableVariable(label='Source Record Id' required=true)
    public Id sourceRecordId;
    @InvocableVariable(label='Content Document Id (PDF)' required=true)
    public Id contentDocumentId;
    @InvocableVariable(
      label='Document Title'
      description='Title signers see in the portal, emails and certificate. Defaults to the file name.'
    )
    public String documentName;
    @InvocableVariable(label='Signer Email')
    public String recipientEmail;
    @InvocableVariable(label='Signer Name')
    public String recipientName;
    @InvocableVariable(
      label='Signer Role'
      description='A value of the SignZero Signer Role picklist; matches {{sig:Role}} tags in the PDF. Defaults to Customer.'
    )
    public String signerRole;
    @InvocableVariable(
      label='Additional Signers'
      description='Optional. Routing order defaults to 2, 3, ... in list order.'
    )
    public List<SignZeroSigner> additionalSigners;
    @InvocableVariable(
      label='Also File On Records'
      description='Optional. Other record Ids that should also get the executed agreement and certificate (the files are shared, not copied).'
    )
    public List<Id> additionalRecordIds;
  }

  /** The envelope that was created, as the invocable action's output. */
  public class DispatchResult {
    @InvocableVariable(label='Signature Request Id')
    public Id signatureRequestId;
  }

  /**
   * Creates the envelopes and invites each one's first routing order.
   * @param requests one per envelope
   * @return the new envelope Ids, in request order
   */
  @InvocableMethod(
    label='Dispatch Document via SignZero'
    description='Sends a PDF from Salesforce Files out for native e-signature.'
    category='SignZero'
  )
  public static List<DispatchResult> execute(List<DispatchRequest> requests) {
    if (!Schema.SObjectType.SignZero_Request__c.isCreateable()) {
      throw new SignZeroSettings.SignZeroException(
        System.Label.SZ_Send_Err_No_Permission
      );
    }
    SignZeroRecordGuard.markProcessUpdate();
    Map<Id, ContentVersion> versions = loadVersions(requests);

    List<SignZero_Request__c> envelopes = new List<SignZero_Request__c>();
    List<List<SignZeroSigner>> signersPerEnvelope = new List<List<SignZeroSigner>>();
    for (DispatchRequest req : requests) {
      ContentVersion cv = versions.get(req.contentDocumentId);
      signersPerEnvelope.add(collectSigners(req));
      String hash = SignZeroSealService.computeSHA256Hash(cv.VersionData);
      envelopes.add(
        new SignZero_Request__c(
          Source_Record_Id__c = req.sourceRecordId,
          Content_Document_Id__c = req.contentDocumentId,
          Document_Name__c = (String.isBlank(req.documentName)
              ? cv.Title
              : req.documentName.trim())
            .left(255),
          Related_Record_Ids__c = req.additionalRecordIds == null
            ? null
            : String.join(req.additionalRecordIds, ','),
          Pre_Sign_Hash__c = hash,
          Working_Copy_Hash__c = hash,
          Status__c = 'Out for Signature'
        )
      );
    }
    insert as system envelopes;

    // The public site's guest user cannot read Salesforce Files, so signers work from an
    // Attachment copy on the envelope. Sealing turns the final copy back into a File.
    List<Attachment> workingCopies = new List<Attachment>();
    for (Integer i = 0; i < envelopes.size(); i++) {
      workingCopies.add(
        new Attachment(
          ParentId = envelopes[i].Id,
          Name = envelopes[i].Document_Name__c.left(251) + '.pdf',
          ContentType = 'application/pdf',
          Body = versions.get(requests[i].contentDocumentId).VersionData
        )
      );
    }
    insert as system workingCopies;
    for (Integer i = 0; i < envelopes.size(); i++) {
      envelopes[i].Working_Copy_Id__c = workingCopies[i].Id;
    }
    update as system envelopes;

    List<SignZero_Recipient__c> recipients = new List<SignZero_Recipient__c>();
    for (Integer i = 0; i < envelopes.size(); i++) {
      for (SignZeroSigner s : signersPerEnvelope[i]) {
        recipients.add(
          new SignZero_Recipient__c(
            SignZero_Request__c = envelopes[i].Id,
            Name = s.name.left(80),
            Email__c = s.email,
            Signer_Role__c = s.role,
            Routing_Order__c = s.routingOrder,
            List_Order__c = s.routingOrder,
            Status__c = 'Pending',
            Auth_Method__c = 'Single-use emailed token link'
          )
        );
      }
    }
    insert as system recipients;

    // Invite the lowest routing order on each envelope; later orders go out as earlier ones sign.
    Map<Id, Decimal> firstOrder = new Map<Id, Decimal>();
    for (SignZero_Recipient__c r : recipients) {
      Decimal current = firstOrder.get(r.SignZero_Request__c);
      if (current == null || r.Routing_Order__c < current) {
        firstOrder.put(r.SignZero_Request__c, r.Routing_Order__c);
      }
    }
    Set<Id> toInvite = new Set<Id>();
    for (SignZero_Recipient__c r : recipients) {
      if (r.Routing_Order__c == firstOrder.get(r.SignZero_Request__c)) {
        toInvite.add(r.Id);
      }
    }
    SignZeroInvitationService.send(toInvite);

    List<DispatchResult> results = new List<DispatchResult>();
    for (SignZero_Request__c env : envelopes) {
      DispatchResult res = new DispatchResult();
      res.signatureRequestId = env.Id;
      results.add(res);
    }
    return results;
  }

  private static Map<Id, ContentVersion> loadVersions(
    List<DispatchRequest> requests
  ) {
    Set<Id> docIds = new Set<Id>();
    for (DispatchRequest req : requests) {
      docIds.add(req.contentDocumentId);
    }
    // Check type and size before pulling any file bodies into the heap.
    Integer maxBytes = SignZeroSettings.maxDocumentBytes();
    Integer total = 0;
    Set<Id> missing = docIds.clone();
    for (ContentVersion cv : [
      SELECT ContentDocumentId, FileType, ContentSize
      FROM ContentVersion
      WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
      WITH USER_MODE
    ]) {
      if (cv.FileType != 'PDF') {
        throw new SignZeroSettings.SignZeroException(
          String.format(
            System.Label.SZ_Send_Err_Not_Pdf,
            new List<Object>{ cv.FileType }
          )
        );
      }
      if (cv.ContentSize > maxBytes) {
        throw new SignZeroSettings.SignZeroException(
          String.format(
            System.Label.SZ_Send_Err_Too_Large,
            new List<Object>{
              String.valueOf(cv.ContentSize / 1024),
              String.valueOf(maxBytes / 1024)
            }
          )
        );
      }
      total += cv.ContentSize;
      missing.remove(cv.ContentDocumentId);
    }
    if (!missing.isEmpty()) {
      throw new SignZeroSettings.SignZeroException(
        String.format(
          System.Label.SZ_Send_Err_File_Not_Found,
          new List<Object>{ String.join(new List<Id>(missing), ', ') }
        )
      );
    }
    if (total > 4 * 1024 * 1024) {
      throw new SignZeroSettings.SignZeroException(
        System.Label.SZ_Send_Err_Too_Much_Data
      );
    }

    Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
    for (ContentVersion cv : [
      SELECT Id, ContentDocumentId, Title, VersionData
      FROM ContentVersion
      WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
      WITH USER_MODE
    ]) {
      result.put(cv.ContentDocumentId, cv);
    }
    return result;
  }

  private static List<SignZeroSigner> collectSigners(DispatchRequest req) {
    List<SignZeroSigner> signers = new List<SignZeroSigner>();
    if (String.isNotBlank(req.recipientEmail)) {
      signers.add(
        new SignZeroSigner(
          req.recipientName,
          req.recipientEmail,
          req.signerRole,
          1
        )
      );
    }
    if (req.additionalSigners != null) {
      Integer nextOrder = signers.size() + 1;
      for (SignZeroSigner s : req.additionalSigners) {
        signers.add(
          new SignZeroSigner(
            s.name,
            s.email,
            s.role,
            s.routingOrder != null ? s.routingOrder : nextOrder
          )
        );
        nextOrder++;
      }
    }
    if (signers.isEmpty()) {
      throw new SignZeroSettings.SignZeroException(
        System.Label.SZ_Send_Err_No_Signer
      );
    }
    Map<String, String> roles = activeRoles();
    for (SignZeroSigner s : signers) {
      if (String.isBlank(s.name)) {
        throw new SignZeroSettings.SignZeroException(
          System.Label.SZ_Send_Err_Signer_Name
        );
      }
      if (String.isBlank(s.email) || !EMAIL.matcher(s.email).matches()) {
        throw new SignZeroSettings.SignZeroException(
          String.format(
            System.Label.SZ_Send_Err_Signer_Email,
            new List<Object>{ s.email }
          )
        );
      }
      if (String.isBlank(s.role)) {
        s.role = 'Customer';
      }
      String role = roles.get(s.role.trim().toLowerCase());
      if (role == null) {
        throw new SignZeroSettings.SignZeroException(
          String.format(
            System.Label.SZ_Send_Err_Signer_Role,
            new List<Object>{ s.role, String.join(roles.values(), ', ') }
          )
        );
      }
      s.role = role;
      if (s.routingOrder == null || s.routingOrder < 1) {
        s.routingOrder = 1;
      }
    }
    return signers;
  }

  /**
   * Active Signer Role values keyed by lower case, so "employer" is accepted and stored as "Employer".
   * @return lower-case value to picklist value
   */
  private static Map<String, String> activeRoles() {
    Map<String, String> roles = new Map<String, String>();
    for (
      Schema.PicklistEntry entry : SignZero_Recipient__c.Signer_Role__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        roles.put(entry.getValue().toLowerCase(), entry.getValue());
      }
    }
    return roles;
  }
}
