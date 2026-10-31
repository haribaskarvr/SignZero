/**
 * The only Apex the public signing site can call. The site guest user has no object permissions;
 * this class runs without sharing and authorises every call by the SHA-256 hash of the signer's token.
 */
public without sharing class SignZeroGatewayController {
  private static final Set<String> OPEN_STATUSES = new Set<String>{
    'Sent',
    'Viewed',
    'Consented'
  };
  private static final Pattern EMAIL_PATTERN = Pattern.compile(
    '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
  );
  // How the signature was adopted in the portal, as shown on the Certificate of Completion.
  private static final Map<String, String> SIGNATURE_METHODS = new Map<String, String>{
    'Typed' => 'Typed in a selected style',
    'Drawn' => 'Drawn on device',
    'Uploaded' => 'Uploaded image'
  };

  /**
   * Opens the signing page. A signer who has already signed can reopen their link to view the latest
   * version read-only (no signing, no declining) until the link expires; that view is logged too.
   * @param rawToken the token from the signing link
   * @param userAgent the signer's browser, for the audit trail
   * @return the document (base64), signer and envelope details, settings and branding for the portal
   */
  @AuraEnabled
  public static Map<String, Object> initializeSession(
    String rawToken,
    String userAgent
  ) {
    SignZero_Recipient__c recipient = findRecipient(rawToken);
    String envelopeStatus = recipient.SignZero_Request__r.Status__c;
    Boolean readOnly = !isSignable(recipient);
    if (
      readOnly &&
      !(recipient.Status__c == 'Signed' &&
      envelopeStatus != 'Voided')
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    // The guest user cannot read Salesforce Files, so signers are served the envelope's Attachment copy.
    Id workingCopyId = recipient.SignZero_Request__r.Working_Copy_Id__c;
    Attachment shown = [
      SELECT Id, BodyLength
      FROM Attachment
      WHERE Id = :workingCopyId
      WITH SYSTEM_MODE
    ];
    if (shown.BodyLength > SignZeroSettings.maxDocumentBytes()) {
      throw fail(System.Label.SZ_Err_Too_Large);
    }
    Blob pdf = [
      SELECT Body
      FROM Attachment
      WHERE Id = :shown.Id
      WITH SYSTEM_MODE
    ]
    .Body;

    String ip = SignZeroAuditService.clientIp();
    if (!readOnly) {
      if (recipient.Status__c == 'Sent') {
        recipient.Status__c = 'Viewed';
        recipient.Viewed_At__c = Datetime.now();
      }
      recipient.Last_Known_IP__c = ip;
      recipient.User_Agent__c = clip(userAgent);
      update as system recipient;
    }
    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      'Viewed'
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.documentHash = recipient.SignZero_Request__r.Working_Copy_Hash__c;
    e.details = readOnly ? 'Read-only view after signing' : null;
    SignZeroAuditService.logOne(e);

    Integer othersToSign = [
      SELECT COUNT()
      FROM SignZero_Recipient__c
      WHERE
        SignZero_Request__c = :recipient.SignZero_Request__c
        AND Id != :recipient.Id
        AND Status__c IN :SignZeroRecordGuard.AWAITING
      WITH SYSTEM_MODE
    ];

    return new Map<String, Object>{
      'recipientName' => recipient.Name,
      'signerRole' => recipient.Signer_Role__c,
      'documentName' => recipient.SignZero_Request__r.Document_Name__c,
      'envelopeNumber' => recipient.SignZero_Request__r.Name,
      'consentAccepted' => recipient.Consented_At__c != null,
      'readOnly' => readOnly,
      'envelopeStatus' => envelopeStatus,
      'signedAt' => recipient.Signed_At__c,
      // The last signer also clears any leftover anchor tags from the document text.
      'isLastSigner' => othersToSign == 0,
      'allowReassign' => !readOnly && SignZeroSettings.allowReassignment(),
      'performanceLogs' => SignZeroSettings.performanceLogs(),
      'pdfHostVersion' => SignZeroSettings.pdfHostVersion(),
      'pdfBase64' => EncodingUtil.base64Encode(pdf),
      'branding' => SignZeroSettings.branding()
    };
  }

  /**
   * Records that the signer accepted the ESIGN/UETA disclosure. Accepting again does nothing.
   * @param rawToken the token from the signing link
   * @param userAgent the signer's browser, for the audit trail
   */
  @AuraEnabled
  public static void recordConsent(String rawToken, String userAgent) {
    SignZero_Recipient__c recipient = openRecipient(rawToken);
    if (recipient.Consented_At__c != null) {
      return;
    }
    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = 'Consented';
    recipient.Consented_At__c = Datetime.now();
    recipient.Last_Known_IP__c = ip;
    update as system recipient;
    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      'Consent Accepted'
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = 'Accepted ESIGN/UETA electronic record and signature disclosure';
    SignZeroAuditService.logOne(e);
  }

  /**
   * Stores the signer's signed copy, marks them Signed and lets the envelope move on.
   * @param rawToken the token from the signing link
   * @param executedPdfBase64 the PDF the signer was shown, with their signature stamped in by the browser
   * @param signatureImageBase64 PNG of a typed or drawn signature, kept as separate evidence. Uploaded
   *        images are never stored on their own; they exist only inside the signed PDF.
   * @param signatureMethod Typed, Drawn or Uploaded
   * @param userAgent the signer's browser, for the audit trail
   * @return isFinalSigner: true when this signature completes the envelope
   */
  @AuraEnabled
  public static Map<String, Object> submitExecutedDocument(
    String rawToken,
    String executedPdfBase64,
    String signatureImageBase64,
    String signatureMethod,
    String userAgent
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken);
    if (recipient.Consented_At__c == null) {
      throw fail(System.Label.SZ_Err_Consent_Required);
    }
    String adoption = SIGNATURE_METHODS.get(signatureMethod);
    if (adoption == null) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    // "%PDF-" encodes to "JVBERi0" in base64.
    if (
      String.isBlank(executedPdfBase64) ||
      !executedPdfBase64.startsWith('JVBERi0')
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Pdf);
    }
    Blob executed = EncodingUtil.base64Decode(executedPdfBase64);
    executedPdfBase64 = null; // release the base64 copy from the heap
    // Allow headroom for the stamped signature images.
    if (executed.size() > SignZeroSettings.maxDocumentBytes() + 512 * 1024) {
      throw fail(System.Label.SZ_Err_Too_Large);
    }
    String executedHash = SignZeroSealService.computeSHA256Hash(executed);
    if (executedHash == recipient.SignZero_Request__r.Working_Copy_Hash__c) {
      throw fail(System.Label.SZ_Err_No_Signature);
    }

    String ip = SignZeroAuditService.clientIp();
    SignZero_Request__c envelope = recipient.SignZero_Request__r;
    Attachment signedCopy = new Attachment(
      ParentId = envelope.Id,
      Name = (envelope.Document_Name__c +
          ' - signed by ' +
          recipient.Name)
          .left(251) + '.pdf',
      ContentType = 'application/pdf',
      Body = executed
    );
    List<Attachment> files = new List<Attachment>{ signedCopy };
    if (
      String.isNotBlank(signatureImageBase64) && signatureMethod != 'Uploaded'
    ) {
      files.add(
        new Attachment(
          ParentId = envelope.Id,
          Name = ('Signature image - ' + recipient.Name).left(251) + '.png',
          ContentType = 'image/png',
          Body = EncodingUtil.base64Decode(signatureImageBase64)
        )
      );
    }
    insert as system files;

    recipient.Status__c = 'Signed';
    recipient.Signature_Method__c = adoption;
    recipient.Signed_At__c = Datetime.now();
    recipient.Last_Known_IP__c = ip;
    recipient.User_Agent__c = clip(userAgent);
    // The link can never sign again (status is Signed); it stays valid for read-only viewing for a while.
    recipient.Token_Expires_At__c = Datetime.now()
      .addDays(SignZeroSettings.tokenValidityDays());
    update as system recipient;
    update as system new SignZero_Request__c(
      Id = envelope.Id,
      Working_Copy_Id__c = signedCopy.Id,
      Working_Copy_Hash__c = executedHash
    );

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      envelope.Id,
      'Signed'
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.documentHash = executedHash;
    e.details =
      'Signed as ' +
      recipient.Signer_Role__c +
      '; signature ' +
      adoption.toLowerCase();
    SignZeroAuditService.logOne(e);

    publish(envelope.Id, 'SIGNED', recipient.Id);

    Integer stillToSign = [
      SELECT COUNT()
      FROM SignZero_Recipient__c
      WHERE
        SignZero_Request__c = :envelope.Id
        AND Status__c IN :SignZeroRecordGuard.AWAITING
      WITH SYSTEM_MODE
    ];
    return new Map<String, Object>{ 'isFinalSigner' => stillToSign == 0 };
  }

  /**
   * Declines to sign, which closes the envelope for everyone.
   * @param rawToken the token from the signing link
   * @param reason why, shown to the sender (optional)
   * @param userAgent the signer's browser, for the audit trail
   */
  @AuraEnabled
  public static void declineToSign(
    String rawToken,
    String reason,
    String userAgent
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken);
    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = 'Declined';
    recipient.Decline_Reason__c = reason == null ? null : reason.left(2000);
    recipient.Last_Known_IP__c = ip;
    recipient.Token_Expires_At__c = Datetime.now();
    update as system recipient;
    update as system new SignZero_Request__c(
      Id = recipient.SignZero_Request__c,
      Status__c = 'Declined'
    );

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      'Declined'
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = reason;
    SignZeroAuditService.logOne(e);

    publish(recipient.SignZero_Request__c, 'DECLINED', recipient.Id);
  }

  /**
   * Delegates this signer's signature to someone else ("Assign to someone else"). The original signer is
   * kept, marked Reassigned with who and why; the new signer takes the same role and routing order and is
   * invited by the progression job, so a failed email can be re-sent rather than losing the reassignment.
   * @param rawToken the token from the signing link
   * @param name the new signer's name
   * @param email the new signer's email address
   * @param reason why, shown to the sender (optional)
   * @param userAgent the signer's browser, for the audit trail
   */
  @AuraEnabled
  public static void reassign(
    String rawToken,
    String name,
    String email,
    String reason,
    String userAgent
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken);
    if (!SignZeroSettings.allowReassignment()) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    name = name == null ? '' : name.trim();
    email = email == null ? '' : email.trim();
    if (String.isBlank(name) || !EMAIL_PATTERN.matcher(email).matches()) {
      throw fail(System.Label.SZ_Reassign_Invalid);
    }
    if (email.equalsIgnoreCase(recipient.Email__c)) {
      throw fail(System.Label.SZ_Reassign_Same);
    }

    SignZero_Recipient__c delegate = new SignZero_Recipient__c(
      SignZero_Request__c = recipient.SignZero_Request__c,
      Name = name.left(80),
      Email__c = email,
      Signer_Role__c = recipient.Signer_Role__c,
      Routing_Order__c = recipient.Routing_Order__c,
      // Listed straight after the person who delegated (2 -> 2.01; a further delegation 2.02).
      List_Order__c = (recipient.List_Order__c == null
        ? recipient.Routing_Order__c
        : recipient.List_Order__c) + 0.01,
      Delegated_From__c = recipient.Id,
      Status__c = 'Pending',
      Auth_Method__c = 'Single-use emailed token link'
    );
    insert as system delegate;

    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = 'Reassigned';
    recipient.Reassigned_To__c = delegate.Id;
    recipient.Reassign_Reason__c = reason == null ? null : reason.left(2000);
    recipient.Last_Known_IP__c = ip;
    recipient.User_Agent__c = clip(userAgent);
    recipient.Token_Expires_At__c = Datetime.now();
    update as system recipient;

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      'Reassigned'
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = ('Reassigned to ' +
      delegate.Name +
      ' <' +
      email +
      '>' +
      (String.isBlank(reason) ? '' : ': ' + reason))
      .left(255);
    SignZeroAuditService.logOne(e);

    publish(recipient.SignZero_Request__c, 'REASSIGNED', delegate.Id);
  }

  /**
   * A recipient whose link may sign (or decline) right now.
   * @param rawToken the token from the signing link
   * @return the recipient, with their envelope
   */
  private static SignZero_Recipient__c openRecipient(String rawToken) {
    SignZero_Recipient__c r = findRecipient(rawToken);
    if (!isSignable(r)) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    return r;
  }

  private static Boolean isSignable(SignZero_Recipient__c r) {
    return OPEN_STATUSES.contains(r.Status__c) &&
      r.SignZero_Request__r.Status__c == 'Out for Signature';
  }

  /**
   * The recipient a live, unexpired token belongs to.
   * @param rawToken the token from the signing link
   * @return the recipient, with their envelope
   */
  private static SignZero_Recipient__c findRecipient(String rawToken) {
    SignZeroRecordGuard.markProcessUpdate();
    if (
      String.isBlank(rawToken) || !Pattern.matches('[0-9a-f]{64}', rawToken)
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    List<SignZero_Recipient__c> rows = [
      SELECT
        Id,
        Name,
        Email__c,
        Signer_Role__c,
        Routing_Order__c,
        List_Order__c,
        Status__c,
        Token_Expires_At__c,
        Consented_At__c,
        Signed_At__c,
        SignZero_Request__c,
        SignZero_Request__r.Name,
        SignZero_Request__r.Status__c,
        SignZero_Request__r.Document_Name__c,
        SignZero_Request__r.Working_Copy_Id__c,
        SignZero_Request__r.Working_Copy_Hash__c
      FROM SignZero_Recipient__c
      WHERE Token_Hash__c = :SignZeroInvitationService.hashToken(rawToken)
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    SignZero_Recipient__c r = rows[0];
    // Checked before expiry: recalling expires every link, and the signer should be told why.
    if (r.SignZero_Request__r.Status__c == 'Voided') {
      throw fail(System.Label.SZ_Err_Recalled);
    }
    if (
      r.Token_Expires_At__c == null ||
      r.Token_Expires_At__c < Datetime.now()
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    return r;
  }

  // EventBus.publish reports failures in its result rather than throwing, so check it: a lost event
  // would leave the envelope stuck with nobody invited and nothing sealed.
  private static void publish(Id requestId, String action, Id recipientId) {
    Database.SaveResult result = EventBus.publish(
      new SignZero_Event__e(
        SignZero_Request_Id__c = requestId,
        Action__c = action,
        Recipient_Id__c = recipientId
      )
    );
    if (!result.isSuccess()) {
      throw new SignZeroSettings.SignZeroException(
        'Could not queue envelope progress: ' +
        result.getErrors()[0].getMessage()
      );
    }
  }

  private static String clip(String s) {
    return s == null ? null : s.left(255);
  }

  private static AuraHandledException fail(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
