/**
 * Seals fully signed envelopes: hashes the executed PDF, optionally signs the hash with an org
 * X.509 certificate, renders the Certificate of Completion, builds a combined "executed + certificate"
 * PDF, and files them on the source record (and any extra records).
 *
 * Called from SignZeroProgressionJob (platform event context). Everything that reads and renders happens
 * before any DML, so a failure leaves the envelope untouched apart from its error message.
 */
public without sharing class SignZeroSealService {
  /**
   * Hashes a file, for the document hashes on the envelope and in the audit trail.
   * @param fileData the file to hash
   * @return its SHA-256 hash, as lower-case hex
   */
  public static String computeSHA256Hash(Blob fileData) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', fileData)
    );
  }

  private class SealContext {
    SignZero_Request__c req;
    Blob executed;
    String postHash;
    String pkiSignature;
    Blob certificate;
    Blob combined; // null when the executed PDF is not in a format SignZeroPdfAppender supports
    ContentVersion finalVersion;
    ContentVersion certVersion;
    ContentVersion combinedVersion;
  }

  /**
   * Seals each envelope, completes it and emails the signers; a failure is recorded on that envelope.
   * @param requestIds envelopes whose signers have all signed
   */
  public static void sealAndFinalize(List<Id> requestIds) {
    SignZeroRecordGuard.markProcessUpdate();
    List<SealContext> contexts = new List<SealContext>();
    Map<Id, SignZero_Request__c> requests = new Map<Id, SignZero_Request__c>(
      [
        SELECT
          Id,
          Name,
          OwnerId,
          Source_Record_Id__c,
          Related_Record_Ids__c,
          Document_Name__c,
          Working_Copy_Id__c,
          (
            SELECT Id, Name, Email__c
            FROM Recipients__r
            ORDER BY Routing_Order__c
          )
        FROM SignZero_Request__c
        WHERE Id IN :requestIds
        WITH SYSTEM_MODE
      ]
    );

    // 1. Everything that does not write: load, hash, sign, render, combine.
    String certName = SignZeroSettings.get().Certificate_Name__c;
    for (Id requestId : requestIds) {
      SignZero_Request__c req = requests.get(requestId);
      SealContext ctx = new SealContext();
      ctx.req = req;
      try {
        ctx.executed = [
          SELECT Body
          FROM Attachment
          WHERE Id = :req.Working_Copy_Id__c
          WITH SYSTEM_MODE
        ]
        .Body;
        ctx.postHash = computeSHA256Hash(ctx.executed);
        if (String.isNotBlank(certName)) {
          ctx.pkiSignature = EncodingUtil.base64Encode(
            Crypto.signWithCertificate('RSA-SHA256', ctx.executed, certName)
          );
        }
        ctx.certificate = SignZeroCertificateController.generateCertificatePdfBlob(
          req.Id,
          ctx.postHash,
          ctx.pkiSignature != null
        );
      } catch (Exception e) {
        req.Error_Message__c = String.format(
          System.Label.SZ_Err_Seal_Failed,
          new List<Object>{ e.getMessage() }
        );
        ctx.executed = null;
      }
      if (ctx.executed != null) {
        try {
          ctx.combined = SignZeroPdfAppender.append(
            ctx.executed,
            ctx.certificate
          );
        } catch (Exception e) {
          // The separate files are the record of truth; the combined copy is a convenience.
          System.debug(
            LoggingLevel.WARN,
            'SignZero could not combine ' + req.Name + ': ' + e.getMessage()
          );
        }
      }
      contexts.add(ctx);
    }

    // 2. Writes.
    List<ContentVersion> files = new List<ContentVersion>();
    for (SealContext ctx : contexts) {
      if (ctx.executed == null) {
        continue;
      }
      Id fileHome = filingRecordId(ctx.req);
      ctx.finalVersion = newFile(
        ctx.req.Document_Name__c + ' - Executed',
        ctx.executed,
        fileHome
      );
      ctx.certVersion = newFile(
        ctx.req.Document_Name__c + ' - Certificate of Completion',
        ctx.certificate,
        fileHome
      );
      files.add(ctx.finalVersion);
      files.add(ctx.certVersion);
      if (ctx.combined != null) {
        ctx.combinedVersion = newFile(
          ctx.req.Document_Name__c + ' - Executed with Certificate',
          ctx.combined,
          fileHome
        );
        files.add(ctx.combinedVersion);
      }
    }
    insert as system files;

    Map<Id, ContentVersion> inserted = new Map<Id, ContentVersion>(
      [
        SELECT Id, ContentDocumentId
        FROM ContentVersion
        WHERE Id IN :files
        WITH SYSTEM_MODE
      ]
    );
    List<ContentDocumentLink> extraLinks = new List<ContentDocumentLink>();
    List<SignZeroAuditService.Entry> audit = new List<SignZeroAuditService.Entry>();
    List<SignZero_Request__c> updates = new List<SignZero_Request__c>();
    for (SealContext ctx : contexts) {
      if (ctx.executed == null) {
        updates.add(
          new SignZero_Request__c(
            Id = ctx.req.Id,
            Error_Message__c = ctx.req.Error_Message__c
          )
        );
        continue;
      }
      List<ContentVersion> versions = new List<ContentVersion>{
        ctx.finalVersion,
        ctx.certVersion
      };
      if (ctx.combinedVersion != null) {
        versions.add(ctx.combinedVersion);
      }
      // One file, shown on every record that needs it: the envelope and any extra records.
      Set<Id> linkTo = extraRecordIds(ctx.req);
      linkTo.add(ctx.req.Id);
      linkTo.remove(filingRecordId(ctx.req)); // already linked through FirstPublishLocationId
      for (Id recordId : linkTo) {
        for (ContentVersion cv : versions) {
          extraLinks.add(
            new ContentDocumentLink(
              ContentDocumentId = inserted.get(cv.Id).ContentDocumentId,
              LinkedEntityId = recordId,
              ShareType = 'V',
              Visibility = 'AllUsers'
            )
          );
        }
      }
      updates.add(
        new SignZero_Request__c(
          Id = ctx.req.Id,
          Status__c = 'Completed',
          Completed_At__c = Datetime.now(),
          Post_Sign_Hash__c = ctx.postHash,
          PKI_Signature__c = ctx.pkiSignature,
          Final_Document_Version_Id__c = ctx.finalVersion.Id,
          Certificate_Version_Id__c = ctx.certVersion.Id,
          Combined_Document_Version_Id__c = ctx.combinedVersion == null
            ? null
            : ctx.combinedVersion.Id,
          Error_Message__c = null
        )
      );
      for (SignZero_Recipient__c r : ctx.req.Recipients__r) {
        SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
          r.Id,
          ctx.req.Id,
          'Completed'
        );
        e.documentHash = ctx.postHash;
        e.details =
          'Envelope sealed' +
          (ctx.pkiSignature == null
            ? ''
            : ' and signed with certificate ' + certName);
        audit.add(e);
      }
    }
    insert as system extraLinks;
    update as system updates;
    SignZeroAuditService.log(audit);

    for (SealContext ctx : contexts) {
      if (ctx.executed != null) {
        SignZeroNotifier.sendExecutedCopies(
          ctx.req,
          ctx.req.Recipients__r,
          ctx.executed,
          ctx.certificate,
          ctx.combined
        );
        SignZeroNotifier.notifyOwner(
          ctx.req,
          'Completed',
          'All parties have signed. The executed agreement and Certificate of Completion are attached to the record.'
        );
      } else {
        SignZeroNotifier.notifyOwner(
          ctx.req,
          'Sealing failed',
          ctx.req.Error_Message__c
        );
      }
    }
  }

  private static ContentVersion newFile(String title, Blob body, Id home) {
    return new ContentVersion(
      Title = title,
      PathOnClient = title + '.pdf',
      VersionData = body,
      FirstPublishLocationId = home
    );
  }

  private static Set<Id> extraRecordIds(SignZero_Request__c req) {
    Set<Id> ids = new Set<Id>();
    if (String.isNotBlank(req.Related_Record_Ids__c)) {
      for (String raw : req.Related_Record_Ids__c.split('[,;\\s]+')) {
        try {
          ids.add(Id.valueOf(raw.trim()));
        } catch (StringException e) {
          // ignore values that are not record Ids
        }
      }
    }
    return ids;
  }

  // Files go on the source record when it is a valid record Id, otherwise on the envelope.
  private static Id filingRecordId(SignZero_Request__c req) {
    if (String.isNotBlank(req.Source_Record_Id__c)) {
      try {
        return Id.valueOf(req.Source_Record_Id__c);
      } catch (StringException e) {
        // fall through
      }
    }
    return req.Id;
  }
}
