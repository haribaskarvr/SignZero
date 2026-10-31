/**
 * Sends SignZero emails: signing invitations to external signers and status notices to envelope owners.
 */
public without sharing class SignZeroNotifier {
  /** One signer to email, with the document they are being emailed about. */
  public class Invitation {
    public String email;
    public String recipientName;
    public String documentName;
    public String signingUrl;
  }

  /**
   * Emails each signer their personal signing link. Throws if the email cannot be sent.
   * @param invitations one per signer
   */
  public static void sendInvitations(List<Invitation> invitations) {
    if (invitations.isEmpty()) {
      return;
    }
    Id fromAddressId = orgWideAddressId();
    String company = SignZeroSettings.branding().get('companyName');
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Invitation inv : invitations) {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ inv.email });
      mail.setSubject('Action Required: Review & Sign ' + inv.documentName);
      mail.setHtmlBody(
        '<p>Hello ' +
          inv.recipientName.escapeHtml4() +
          ',</p>' +
          '<p>' +
          company.escapeHtml4() +
          ' has sent you <strong>' +
          inv.documentName.escapeHtml4() +
          '</strong> to review and sign.</p>' +
          '<p><a href="' +
          inv.signingUrl +
          '">Open your secure signing session</a></p>' +
          '<p style="color:#666;font-size:12px">This link is personal to you and expires in ' +
          SignZeroSettings.tokenValidityDays() +
          ' days. Do not forward it.</p>'
      );
      mail.setPlainTextBody(
        'Hello ' +
          inv.recipientName +
          ',\n\n' +
          company +
          ' has sent you "' +
          inv.documentName +
          '" to review and sign.\n\nOpen your secure signing session:\n' +
          inv.signingUrl +
          '\n\nThis link is personal to you. Do not forward it.'
      );
      mail.setSaveAsActivity(false);
      if (fromAddressId != null) {
        mail.setOrgWideEmailAddressId(fromAddressId);
      }
      mails.add(mail);
    }
    send(mails);
  }

  /**
   * Tells signers who were sent an envelope that the sender recalled it. Throws if the email cannot be sent,
   * so the caller can record that the signers were not told.
   * @param recipients one per signer to tell (the signing URL is not used)
   * @param reason the sender's reason, included when given
   */
  public static void sendCancellations(
    List<Invitation> recipients,
    String reason
  ) {
    if (recipients.isEmpty()) {
      return;
    }
    Id fromAddressId = orgWideAddressId();
    String company = SignZeroSettings.branding().get('companyName');
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Invitation inv : recipients) {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ inv.email });
      mail.setSubject('Recalled: ' + inv.documentName);
      mail.setHtmlBody(
        '<p>Hello ' +
          inv.recipientName.escapeHtml4() +
          ',</p>' +
          '<p>' +
          company.escapeHtml4() +
          ' has recalled <strong>' +
          inv.documentName.escapeHtml4() +
          '</strong>. The signing request is cancelled and any signing link you received for it no longer works.</p>' +
          (String.isBlank(reason)
            ? ''
            : '<p>Reason: ' + reason.escapeHtml4() + '</p>') +
          '<p>No further action is needed from you.</p>'
      );
      mail.setPlainTextBody(
        'Hello ' +
          inv.recipientName +
          ',\n\n' +
          company +
          ' has recalled "' +
          inv.documentName +
          '". The signing request is cancelled and any signing link you received for it no longer works.\n\n' +
          (String.isBlank(reason) ? '' : 'Reason: ' + reason + '\n\n') +
          'No further action is needed from you.'
      );
      mail.setSaveAsActivity(false);
      if (fromAddressId != null) {
        mail.setOrgWideEmailAddressId(fromAddressId);
      }
      mails.add(mail);
    }
    send(mails);
  }

  /**
   * Emails every signer the completed agreement, as e-signature services do, so each party holds an
   * independent copy: one combined PDF (agreement followed by its Certificate of Completion) when it could
   * be built, otherwise the two files. Best effort: a failure here never undoes a completed seal.
   * @param req the completed envelope
   * @param signers everyone to email
   * @param executed the executed agreement
   * @param certificate the Certificate of Completion
   * @param combined agreement and certificate in one PDF, or null when it could not be built
   */
  public static void sendExecutedCopies(
    SignZero_Request__c req,
    List<SignZero_Recipient__c> signers,
    Blob executed,
    Blob certificate,
    Blob combined
  ) {
    try {
      List<String> to = new List<String>();
      for (SignZero_Recipient__c r : signers) {
        to.add(r.Email__c);
      }
      if (to.isEmpty()) {
        return;
      }
      List<Messaging.EmailFileAttachment> files = combined != null
        ? new List<Messaging.EmailFileAttachment>{
            pdf(
              req.Document_Name__c + ' - Executed with Certificate.pdf',
              combined
            )
          }
        : new List<Messaging.EmailFileAttachment>{
            pdf(req.Document_Name__c + ' - Executed.pdf', executed),
            pdf(
              req.Document_Name__c + ' - Certificate of Completion.pdf',
              certificate
            )
          };

      String company = SignZeroSettings.branding().get('companyName');
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(to);
      mail.setSubject('Completed: ' + req.Document_Name__c);
      mail.setPlainTextBody(
        'All parties have signed "' +
          req.Document_Name__c +
          '" (envelope ' +
          req.Name +
          ').\n\n' +
          'The executed agreement and its Certificate of Completion are attached for your records.\n\n' +
          company
      );
      mail.setFileAttachments(files);
      mail.setSaveAsActivity(false);
      Id fromAddressId = orgWideAddressId();
      if (fromAddressId != null) {
        mail.setOrgWideEmailAddressId(fromAddressId);
      }
      send(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'SignZero completion email failed: ' + e.getMessage()
      );
    }
  }

  /**
   * Best-effort email and bell notification to the envelope owner. Failures are swallowed so they never block sealing.
   * @param req the envelope (Id, Name, OwnerId, Document_Name__c)
   * @param outcome what happened, e.g. Completed or Declined
   * @param message the notice text
   */
  public static void notifyOwner(
    SignZero_Request__c req,
    String outcome,
    String message
  ) {
    bell(
      req,
      req.Document_Name__c + ': ' + outcome,
      req.Name + ' - ' + message
    );
    try {
      if (
        req.OwnerId == null ||
        req.OwnerId.getSobjectType() != User.SObjectType
      ) {
        return;
      }
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setTargetObjectId(req.OwnerId);
      mail.setSaveAsActivity(false);
      mail.setSubject(
        'SignZero ' + req.Name + ' ' + outcome + ': ' + req.Document_Name__c
      );
      mail.setPlainTextBody(
        message + '\n\n' + URL.getOrgDomainUrl().toExternalForm() + '/' + req.Id
      );
      send(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'SignZero owner notification failed: ' + e.getMessage()
      );
    }
  }

  /**
   * Bell notification (desktop and mobile) to the envelope owner, opening the envelope when clicked.
   * Best effort, like the emails.
   * @param req the envelope (Id, OwnerId)
   * @param title notification title
   * @param body notification text
   */
  public static void bell(SignZero_Request__c req, String title, String body) {
    try {
      if (
        req.OwnerId == null ||
        req.OwnerId.getSobjectType() != User.SObjectType
      ) {
        return;
      }
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = 'SignZero_Status_Update'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (types.isEmpty()) {
        return;
      }
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(types[0].Id);
      notification.setTargetId(req.Id);
      notification.setTitle(title.left(250));
      notification.setBody(body.left(750));
      notification.send(new Set<String>{ (String) req.OwnerId });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'SignZero bell notification failed: ' + e.getMessage()
      );
    }
  }

  /** Emails sent during a test run, captured instead of sent so tests never use up the org's daily email limit. */
  @TestVisible
  private static List<Messaging.SingleEmailMessage> sentInTest = new List<Messaging.SingleEmailMessage>();
  @TestVisible
  private static Boolean failSendsInTest = false;

  private static void send(List<Messaging.SingleEmailMessage> mails) {
    if (Test.isRunningTest()) {
      if (failSendsInTest) {
        throw new EmailException('SINGLE_EMAIL_LIMIT_EXCEEDED (simulated)');
      }
      sentInTest.addAll(mails);
      return;
    }
    Messaging.sendEmail(mails);
  }

  private static Messaging.EmailFileAttachment pdf(String fileName, Blob body) {
    Messaging.EmailFileAttachment file = new Messaging.EmailFileAttachment();
    file.setFileName(fileName);
    file.setContentType('application/pdf');
    file.setBody(body);
    return file;
  }

  private static Id orgWideAddressId() {
    String address = SignZeroSettings.get().Org_Wide_Email_Address__c;
    if (String.isBlank(address)) {
      return null;
    }
    List<OrgWideEmailAddress> rows = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :address
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }
}
