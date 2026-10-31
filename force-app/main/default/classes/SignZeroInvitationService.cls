/**
 * Issues single-use signing tokens and emails them. A fresh token is minted at send time, so the raw
 * token only ever exists in memory and in the email; the database keeps its SHA-256 hash.
 */
public without sharing class SignZeroInvitationService {
  /**
   * Hashes a signing token, so the raw token is never stored.
   * @param rawToken a signing token
   * @return its SHA-256 hash, as stored on the recipient
   */
  public static String hashToken(String rawToken) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(rawToken))
    );
  }

  /**
   * Emails each recipient a new signing link.
   * @param recipientIds recipients to (re)invite; any previous token for them stops working.
   */
  public static void send(Set<Id> recipientIds) {
    send(recipientIds, null);
  }

  /**
   * Emails each recipient a new signing link and logs it in the audit trail.
   * @param recipientIds recipients to (re)invite; any previous token for them stops working.
   * @param note added to the audit entry, e.g. who re-sent the invitation
   */
  public static void send(Set<Id> recipientIds, String note) {
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
        SignZero_Request__c,
        SignZero_Request__r.Document_Name__c
      FROM SignZero_Recipient__c
      WHERE Id IN :recipientIds
      WITH SYSTEM_MODE
    ];
    String baseUrl = SignZeroSettings.signingBaseUrl();
    Datetime now = Datetime.now();
    Datetime expiry = now.addDays(SignZeroSettings.tokenValidityDays());

    List<SignZeroNotifier.Invitation> invitations = new List<SignZeroNotifier.Invitation>();
    List<SignZeroAuditService.Entry> audit = new List<SignZeroAuditService.Entry>();
    for (SignZero_Recipient__c r : recipients) {
      String rawToken = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
      r.Token_Hash__c = hashToken(rawToken);
      r.Token_Expires_At__c = expiry;
      // A resend keeps a signer's progress (viewed, consented); only a first invitation moves them to Sent.
      if (r.Status__c == 'Pending') {
        r.Status__c = 'Sent';
      }
      r.Sent_At__c = now;

      SignZeroNotifier.Invitation inv = new SignZeroNotifier.Invitation();
      inv.email = r.Email__c;
      inv.recipientName = r.Name;
      inv.documentName = r.SignZero_Request__r.Document_Name__c;
      inv.signingUrl = baseUrl + '?token=' + rawToken;
      invitations.add(inv);

      SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
        r.Id,
        r.SignZero_Request__c,
        'Sent'
      );
      e.details = ('Invitation emailed to ' +
        r.Email__c +
        (note == null ? '' : ' (' + note + ')'))
        .left(255);
      audit.add(e);
    }
    update as system recipients;
    SignZeroAuditService.log(audit);
    SignZeroNotifier.sendInvitations(invitations);
  }
}
