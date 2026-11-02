/**
 * @description "Recall Envelope" quick action: the sender voids an envelope still out for signature. Recalling closes
 *   every signing link, voids unsigned signers, logs the recall and emails everyone already sent the envelope. The
 *   sender needs edit access.
 */
public with sharing class SignZeroRecallController {
  /**
   * @description Outcome of a recall, for the toast.
   */
  public class Result {
    /** @description How many signers were sent the cancellation email. */
    @AuraEnabled
    public Integer notified;
    /** @description Set when the envelope was recalled but the cancellation email could not be sent. */
    @AuraEnabled
    public String warning;
  }

  /**
   * @description Lists who will be told, for the confirmation screen. Throws a readable reason if the envelope cannot
   *   be recalled.
   * @param recordId the Signature Request
   * @return the signers who will get a cancellation email
   */
  @AuraEnabled
  public static List<SignZeroResendController.Target> previewRecall(
    Id recordId
  ) {
    List<SignZeroResendController.Target> targets = new List<SignZeroResendController.Target>();
    for (SignZero_Recipient__c r : alreadySent(loadRecallable(recordId))) {
      SignZeroResendController.Target t = new SignZeroResendController.Target();
      t.name = r.Name;
      t.email = r.Email__c;
      targets.add(t);
    }
    return targets;
  }

  /**
   * @description Recalls (voids) the envelope. Throws a readable reason if it cannot be recalled.
   * @param recordId the Signature Request
   * @param reason the sender's reason (optional), emailed to the signers and kept in the audit trail
   * @return how many signers were emailed, and a warning if the email failed
   */
  @AuraEnabled
  public static Result recall(Id recordId, String reason) {
    SignZero_Request__c envelope = loadRecallable(recordId);
    reason = String.isBlank(reason) ? null : reason.trim().left(SignZeroConstants.MAX_RECALL_REASON);
    SignZeroRecordGuard.markProcessUpdate();

    String details = ('Recalled by ' +
      UserInfo.getName() +
      ' (' +
      UserInfo.getUserName() +
      ')' +
      (reason == null ? '' : ': ' + reason))
      .left(255);
    voidEnvelope(envelope, reason, details);
    Result result = sendCancellations(envelope, reason);

    if (envelope.OwnerId != UserInfo.getUserId()) {
      SignZeroNotifier.notifyOwner(
        envelope,
        System.Label.SZ_Outcome_Recalled,
        SignZeroNotifier.fill(
          System.Label.SZ_Owner_Recalled,
          new List<Object>{ UserInfo.getName() }
        ) +
          (reason == null
            ? ''
            : ' ' +
              SignZeroNotifier.fill(
                System.Label.SZ_Mail_Reason,
                new List<Object>{ reason }
              ))
      );
    }
    return result;
  }

  /**
   * @description Voids the envelope and the signers who had not signed, closes every link and logs a Recalled event per
   *   signer.
   * @param envelope the envelope, with its signers
   * @param reason the sender's reason, or null
   * @param details the audit entry text (who recalled it and why)
   */
  private static void voidEnvelope(
    SignZero_Request__c envelope,
    String reason,
    String details
  ) {
    Datetime now = Datetime.now();
    String ip = SignZeroAuditService.clientIp();
    List<SignZero_Recipient__c> recipients = new List<SignZero_Recipient__c>();
    List<SignZeroAuditService.Entry> audit = new List<SignZeroAuditService.Entry>();
    for (SignZero_Recipient__c r : envelope.Recipients__r) {
      SignZero_Recipient__c row = new SignZero_Recipient__c(Id = r.Id);
      if (SignZeroConstants.SIGNER_AWAITING.contains(r.Status__c)) {
        row.Status__c = SignZeroConstants.SIGNER_VOIDED;
      }
      // Including signed signers' read-only links.
      if (r.Token_Expires_At__c != null && r.Token_Expires_At__c > now) {
        row.Token_Expires_At__c = now;
      }
      row.Token_Encrypted__c = null;
      recipients.add(row);

      SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
        r.Id,
        envelope.Id,
        SignZeroConstants.EVENT_RECALLED
      );
      e.ipAddress = ip;
      e.documentHash = envelope.Working_Copy_Hash__c;
      e.details = details;
      audit.add(e);
    }
    update as system new SignZero_Request__c(
      Id = envelope.Id,
      Status__c = SignZeroConstants.ENVELOPE_VOIDED,
      Recall_Reason__c = reason,
      Error_Message__c = null
    );
    update as system recipients;
    SignZeroAuditService.log(audit);
  }

  /**
   * @description Emails the cancellation to everyone who was sent a link. The recall stands if the email fails; the
   *   sender is told and the problem is kept on the envelope.
   * @param envelope the recalled envelope, with its signers
   * @param reason the sender's reason, or null
   * @return how many signers were emailed, and a warning if the email failed
   */
  private static Result sendCancellations(
    SignZero_Request__c envelope,
    String reason
  ) {
    Result result = new Result();
    List<SignZeroNotifier.Invitation> notices = new List<SignZeroNotifier.Invitation>();
    for (SignZero_Recipient__c r : alreadySent(envelope)) {
      SignZeroNotifier.Invitation n = new SignZeroNotifier.Invitation();
      n.email = r.Email__c;
      n.recipientName = r.Name;
      n.documentName = envelope.Document_Name__c;
      notices.add(n);
    }
    try {
      SignZeroNotifier.sendCancellations(notices, reason);
      result.notified = notices.size();
    } catch (Exception e) {
      result.notified = 0;
      result.warning = String.format(
        System.Label.SZ_Recall_Email_Failed,
        new List<Object>{ e.getMessage() }
      );
      update as system new SignZero_Request__c(
        Id = envelope.Id,
        Error_Message__c = result.warning
      );
    }
    return result;
  }

  /**
   * @description Loads the envelope if the user can edit it and it is still out for signature.
   * @param recordId the Signature Request
   * @return the envelope, with its signers
   */
  private static SignZero_Request__c loadRecallable(Id recordId) {
    List<SignZero_Request__c> envelopes = [
      SELECT
        Id,
        Name,
        OwnerId,
        Status__c,
        Document_Name__c,
        Working_Copy_Hash__c,
        (
          SELECT Id, Name, Email__c, Status__c, Sent_At__c, Token_Expires_At__c
          FROM Recipients__r
          ORDER BY Routing_Order__c, List_Order__c
        )
      FROM SignZero_Request__c
      WHERE Id = :recordId
      WITH USER_MODE
    ];
    if (envelopes.isEmpty()) {
      throw fail(System.Label.SZ_Recall_Err_Not_Found);
    }
    SignZero_Request__c envelope = envelopes[0];
    if (envelope.Status__c != SignZeroConstants.ENVELOPE_OUT_FOR_SIGNATURE) {
      throw fail(refusal(envelope.Status__c));
    }
    if (
      ![
        SELECT RecordId, HasEditAccess
        FROM UserRecordAccess
        WHERE UserId = :UserInfo.getUserId() AND RecordId = :envelope.Id
      ]
      .HasEditAccess
    ) {
      throw fail(System.Label.SZ_Recall_Err_No_Access);
    }
    return envelope;
  }

  /**
   * @description Explains why an envelope in this status cannot be recalled.
   * @param status the envelope status (anything but Out for Signature)
   * @return the message for the sender
   */
  private static String refusal(String status) {
    // Not a switch: switch values must be literals.
    if (status == SignZeroConstants.ENVELOPE_COMPLETED) {
      return System.Label.SZ_Recall_Err_Completed;
    }
    if (status == SignZeroConstants.ENVELOPE_SEALING) {
      return System.Label.SZ_Recall_Err_Sealing;
    }
    if (status == SignZeroConstants.ENVELOPE_DECLINED) {
      return System.Label.SZ_Recall_Err_Declined;
    }
    if (status == SignZeroConstants.ENVELOPE_VOIDED) {
      return System.Label.SZ_Recall_Err_Already;
    }
    return String.format(
      System.Label.SZ_Recall_Err_Status,
      new List<Object>{ status }
    );
  }

  /**
   * @description Lists the signers who were emailed a link; anyone not yet invited never heard of the envelope.
   * @param envelope the envelope, with its signers
   * @return the signers with a Sent At time
   */
  private static List<SignZero_Recipient__c> alreadySent(
    SignZero_Request__c envelope
  ) {
    List<SignZero_Recipient__c> sent = new List<SignZero_Recipient__c>();
    for (SignZero_Recipient__c r : envelope.Recipients__r) {
      if (r.Sent_At__c != null) {
        sent.add(r);
      }
    }
    return sent;
  }

  /**
   * @description Builds an error the quick action shows as is.
   * @param message the message for the sender
   * @return the exception to throw
   */
  private static AuraHandledException fail(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
