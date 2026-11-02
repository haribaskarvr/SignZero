/**
 * @description Issues signing tokens and emails them. Only the token's hash and an encrypted copy (for reminders) are
 *   stored; invitations and manual resends always mint a new token.
 */
public without sharing class SignZeroInvitationService {
  /**
   * @description Hashes a signing token, so the raw token is never stored.
   * @param rawToken a signing token
   * @return its SHA-256 hash, as stored on the recipient
   */
  public static String hashToken(String rawToken) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(rawToken))
    );
  }

  /**
   * @description Emails each recipient a new signing link; earlier links stop working.
   * @param recipientIds recipients to invite or re-invite
   */
  public static void send(Set<Id> recipientIds) {
    send(recipientIds, null);
  }

  /**
   * @description Emails each recipient a new signing link and logs it in the audit trail; earlier links stop working.
   * @param recipientIds recipients to invite or re-invite
   * @param note added to the audit entry, e.g. who re-sent the invitation
   */
  public static void send(Set<Id> recipientIds, String note) {
    issue(recipientIds, note, false);
  }

  /**
   * @description Emails each recipient an automatic reminder with their current link and a later expiry; a new link
   *   only when the old one cannot be recovered. The last allowed reminder is marked final.
   * @param recipientIds recipients whose reminder is due
   */
  public static void sendReminders(Set<Id> recipientIds) {
    issue(recipientIds, null, true);
  }

  /**
   * @description Shared by invitations, resends and reminders: sets each recipient's link and expiry, emails them and
   *   logs it.
   * @param recipientIds the recipients
   * @param note added to the audit entry, or null
   * @param reminder true for an automatic reminder, which keeps the current link and counts the reminder
   */
  private static void issue(Set<Id> recipientIds, String note, Boolean reminder) {
    SignZeroRecordGuard.markProcessUpdate();
    if (recipientIds.isEmpty()) {
      return;
    }
    List<SignZero_Recipient__c> recipients = [
      SELECT
        Id,
        Name,
        Email__c,
        Status__c,
        Token_Hash__c,
        Token_Encrypted__c,
        Reminders_Sent__c,
        SignZero_Request__c,
        SignZero_Request__r.Document_Name__c
      FROM SignZero_Recipient__c
      WHERE Id IN :recipientIds
      WITH SYSTEM_MODE
    ];
    String baseUrl = SignZeroSettings.signingBaseUrl();
    Datetime now = Datetime.now();
    Datetime expiry = now.addDays(SignZeroSettings.tokenValidityDays());
    Integer reminderLimit = SignZeroSettings.reminderLimit();

    List<SignZeroNotifier.Invitation> invitations = new List<SignZeroNotifier.Invitation>();
    List<SignZeroAuditService.Entry> audit = new List<SignZeroAuditService.Entry>();
    for (SignZero_Recipient__c r : recipients) {
      // Reminders re-send the current link; everything else gets a new one.
      String rawToken = reminder
        ? SignZeroTokenVault.decrypt(r.Token_Encrypted__c, r.Token_Hash__c)
        : null;
      Boolean newLink = rawToken == null;
      if (newLink) {
        rawToken = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
        r.Token_Hash__c = hashToken(rawToken);
        r.Token_Encrypted__c = SignZeroTokenVault.encrypt(rawToken);
        // A new link needs a new passcode, and may ask for codes again.
        r.Passcode_Hash__c = null;
        r.Passcode_Expires_At__c = null;
        r.Passcode_Attempts__c = 0;
        r.Passcode_Sends__c = 0;
        r.Passcode_Sent_At__c = null;
        r.Passcode_Session_Hash__c = null;
      }
      r.Token_Expires_At__c = expiry;
      // A resend keeps the signer's progress; only a first invitation moves them to Sent.
      if (r.Status__c == SignZeroConstants.SIGNER_PENDING) {
        r.Status__c = SignZeroConstants.SIGNER_SENT;
      }
      r.Sent_At__c = now;
      r.Expiry_Notified_At__c = null;
      // Invitations and manual resends restart the reminder schedule.
      Integer reminderNumber = reminder
        ? (r.Reminders_Sent__c == null ? 0 : r.Reminders_Sent__c.intValue()) + 1
        : 0;
      r.Reminders_Sent__c = reminderNumber;

      SignZeroNotifier.Invitation inv = new SignZeroNotifier.Invitation();
      inv.email = r.Email__c;
      inv.recipientName = r.Name;
      inv.documentName = r.SignZero_Request__r.Document_Name__c;
      inv.signingUrl = baseUrl + '?token=' + rawToken;
      inv.expiresAt = expiry;
      inv.reminder = reminder;
      inv.finalReminder = reminder && reminderNumber >= reminderLimit;
      inv.newLink = reminder && newLink;
      invitations.add(inv);

      SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
        r.Id,
        r.SignZero_Request__c,
        SignZeroConstants.EVENT_SENT
      );
      String detail = reminder
        ? 'reminder ' + reminderNumber + ' of ' + reminderLimit
        : note;
      e.details = ((reminder ? 'Reminder emailed to ' : 'Invitation emailed to ') +
        r.Email__c +
        (detail == null ? '' : ' (' + detail + ')'))
        .left(255);
      audit.add(e);
    }
    update as system recipients;
    SignZeroAuditService.log(audit);
    SignZeroNotifier.sendInvitations(invitations);
  }
}
