/**
 * @description Sends SignZero emails: signing invitations to signers and status notices to envelope owners.
 */
public without sharing class SignZeroNotifier {
  /**
   * @description One signer to email, with the document they are emailed about.
   */
  public class Invitation {
    /** @description Signer's email address. */
    public String email;
    /** @description Signer's name. */
    public String recipientName;
    /** @description Document title shown in the email. */
    public String documentName;
    /** @description The signer's personal signing link. */
    public String signingUrl;
    /** @description When the signing link stops working. */
    public Datetime expiresAt;
    /** @description An automatic reminder rather than a first invitation or resend. */
    public Boolean reminder = false;
    /** @description The last automatic reminder this signer will get. */
    public Boolean finalReminder = false;
    /** @description A reminder whose link replaces the one sent before. */
    public Boolean newLink = false;
  }

  /**
   * @description Emails each signer their personal signing link.
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
      String subject = inv.finalReminder
        ? System.Label.SZ_Mail_Final_Reminder_Subject
        : inv.reminder
            ? System.Label.SZ_Mail_Reminder_Subject
            : System.Label.SZ_Mail_Invite_Subject;
      mail.setSubject(fill(subject, new List<Object>{ inv.documentName }));
      String intro = inv.reminder
        ? System.Label.SZ_Mail_Reminder_Intro
        : System.Label.SZ_Mail_Invite_Intro;
      // Reminders give the date, since they may be read days later.
      String footer = inv.reminder && inv.expiresAt != null
        ? fill(
            System.Label.SZ_Mail_Reminder_Expiry,
            new List<Object>{ inv.expiresAt.format('d MMMM yyyy') }
          )
        : fill(
            System.Label.SZ_Mail_Invite_Expiry,
            new List<Object>{ SignZeroSettings.tokenValidityDays() }
          );
      if (inv.finalReminder) {
        footer = System.Label.SZ_Mail_Final_Reminder_Note + ' ' + footer;
      }
      if (inv.newLink) {
        footer += ' ' + System.Label.SZ_Mail_New_Link_Note;
      }
      mail.setHtmlBody(
        logoHtml() +
          paragraph(
            System.Label.SZ_Mail_Greeting,
            new List<Object>{ inv.recipientName }
          ) +
          paragraph(
            intro,
            new List<Object>{ company, strong(inv.documentName) }
          ) +
          '<p><a href="' +
          inv.signingUrl +
          '">' +
          System.Label.SZ_Mail_Open_Link.escapeHtml4() +
          '</a></p>' +
          '<p style="color:#666;font-size:12px">' +
          footer.escapeHtml4() +
          '</p>'
      );
      mail.setPlainTextBody(
        fill(System.Label.SZ_Mail_Greeting, new List<Object>{ inv.recipientName }) +
          '\n\n' +
          fill(intro, new List<Object>{ company, '"' + inv.documentName + '"' }) +
          '\n\n' +
          System.Label.SZ_Mail_Open_Link +
          ':\n' +
          inv.signingUrl +
          '\n\n' +
          footer
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
   * @description Emails a signer the one-time passcode that opens their document.
   * @param inv the signer and document (the signing URL is not used)
   * @param code the passcode
   */
  public static void sendPasscode(Invitation inv, String code) {
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ inv.email });
    mail.setSubject(
      fill(System.Label.SZ_Mail_Passcode_Subject, new List<Object>{ inv.documentName })
    );
    String note = fill(
      System.Label.SZ_Mail_Passcode_Note,
      new List<Object>{ SignZeroConstants.PASSCODE_VALID_MINUTES }
    );
    mail.setHtmlBody(
      logoHtml() +
        paragraph(System.Label.SZ_Mail_Greeting, new List<Object>{ inv.recipientName }) +
        paragraph(System.Label.SZ_Mail_Passcode_Intro, new List<Object>{ strong(inv.documentName) }) +
        '<p style="font-size:28px;font-weight:bold;letter-spacing:6px">' +
        code +
        '</p>' +
        '<p style="color:#666;font-size:12px">' +
        note.escapeHtml4() +
        '</p>'
    );
    mail.setPlainTextBody(
      fill(System.Label.SZ_Mail_Greeting, new List<Object>{ inv.recipientName }) +
        '\n\n' +
        fill(System.Label.SZ_Mail_Passcode_Intro, new List<Object>{ '"' + inv.documentName + '"' }) +
        '\n\n' +
        code +
        '\n\n' +
        note
    );
    mail.setSaveAsActivity(false);
    Id fromAddressId = orgWideAddressId();
    if (fromAddressId != null) {
      mail.setOrgWideEmailAddressId(fromAddressId);
    }
    send(new List<Messaging.SingleEmailMessage>{ mail });
  }

  /**
   * @description Tells signers who were sent an envelope that the sender recalled it. Throws if the email cannot be
   *   sent, so the caller can record that the signers were not told.
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
      mail.setSubject(
        fill(
          System.Label.SZ_Mail_Recall_Subject,
          new List<Object>{ inv.documentName }
        )
      );
      mail.setHtmlBody(
        logoHtml() +
          paragraph(
            System.Label.SZ_Mail_Greeting,
            new List<Object>{ inv.recipientName }
          ) +
          paragraph(
            System.Label.SZ_Mail_Recall_Intro,
            new List<Object>{ company, strong(inv.documentName) }
          ) +
          (String.isBlank(reason)
            ? ''
            : paragraph(System.Label.SZ_Mail_Reason, new List<Object>{ reason })) +
          paragraph(System.Label.SZ_Mail_No_Action, new List<Object>())
      );
      mail.setPlainTextBody(
        fill(System.Label.SZ_Mail_Greeting, new List<Object>{ inv.recipientName }) +
          '\n\n' +
          fill(
            System.Label.SZ_Mail_Recall_Intro,
            new List<Object>{ company, '"' + inv.documentName + '"' }
          ) +
          '\n\n' +
          (String.isBlank(reason)
            ? ''
            : fill(System.Label.SZ_Mail_Reason, new List<Object>{ reason }) +
              '\n\n') +
          System.Label.SZ_Mail_No_Action
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
   * @description Emails every signer the completed agreement and its Certificate of Completion, combined into one PDF
   *   when possible. Best effort: a failure never undoes the seal.
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
      List<Object> document = new List<Object>{ req.Document_Name__c };
      List<Messaging.EmailFileAttachment> files = combined != null
        ? new List<Messaging.EmailFileAttachment>{
            pdf(
              fill(System.Label.SZ_File_Executed_With_Certificate, document),
              combined
            )
          }
        : new List<Messaging.EmailFileAttachment>{
            pdf(fill(System.Label.SZ_File_Executed, document), executed),
            pdf(fill(System.Label.SZ_File_Certificate, document), certificate)
          };

      String company = SignZeroSettings.branding().get('companyName');
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(to);
      mail.setSubject(fill(System.Label.SZ_Mail_Completed_Subject, document));
      mail.setPlainTextBody(
        fill(
          System.Label.SZ_Mail_Completed_Intro,
          new List<Object>{ req.Document_Name__c, req.Name }
        ) +
          '\n\n' +
          System.Label.SZ_Mail_Completed_Attached +
          '\n\n' +
          company
      );
      mail.setHtmlBody(
        logoHtml() +
          paragraph(
            System.Label.SZ_Mail_Completed_Intro,
            new List<Object>{ req.Document_Name__c, req.Name }
          ) +
          paragraph(System.Label.SZ_Mail_Completed_Attached, new List<Object>()) +
          '<p>' +
          company.escapeHtml4() +
          '</p>'
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
   * @description Emails and notifies the envelope owner. Best effort: failures never block sealing.
   * @param req the envelope (Id, Name, OwnerId, Document_Name__c)
   * @param outcome what happened, e.g. Completed or Declined
   * @param message the notice text
   */
  public static void notifyOwner(
    SignZero_Request__c req,
    String outcome,
    String message
  ) {
    bell(req, bellTitle(req, outcome), bellBody(req, message));
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
        fill(
          System.Label.SZ_Owner_Subject,
          new List<Object>{ req.Name, outcome, req.Document_Name__c }
        )
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
   * @description Sends the envelope owner a bell notification that opens the envelope. Best effort, like the emails.
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
        WHERE DeveloperName = :SignZeroConstants.NOTIFICATION_TYPE
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

  /** @description Emails captured during tests instead of sent, so tests never use the org's daily email limit. */
  @TestVisible
  private static List<Messaging.SingleEmailMessage> sentInTest = new List<Messaging.SingleEmailMessage>();
  @TestVisible
  private static Boolean failSendsInTest = false;

  /**
   * @description Sends emails, or captures them during tests.
   * @param mails the emails
   */
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

  /**
   * @description Builds a PDF email attachment.
   * @param fileName the attachment's file name
   * @param body the PDF
   * @return the attachment
   */
  private static Messaging.EmailFileAttachment pdf(String fileName, Blob body) {
    Messaging.EmailFileAttachment file = new Messaging.EmailFileAttachment();
    file.setFileName(fileName);
    file.setContentType(SignZeroConstants.PDF_CONTENT_TYPE);
    file.setBody(body);
    return file;
  }

  /**
   * @description Finds the org-wide address set in SignZero Branding.
   * @return its Id, or null to send from the running user's address
   */
  private static Id orgWideAddressId() {
    String address = SignZeroSettings.orgWideEmailAddress();
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

  /**
   * @description Fills a Custom Label's {0}, {1}... placeholders.
   * @param label the label text
   * @param values the values, in order
   * @return the filled text
   */
  public static String fill(String label, List<Object> values) {
    return String.format(label, values);
  }

  /**
   * @description Builds a bell notification title: "Document: what happened".
   * @param req the envelope (Document_Name__c)
   * @param what what happened
   * @return the title
   */
  public static String bellTitle(SignZero_Request__c req, String what) {
    return fill(
      System.Label.SZ_Bell_Title,
      new List<Object>{ req.Document_Name__c, what }
    );
  }

  /**
   * @description Builds a bell notification text: "Envelope - details".
   * @param req the envelope (Name)
   * @param details the details
   * @return the text
   */
  public static String bellBody(SignZero_Request__c req, String details) {
    return fill(
      System.Label.SZ_Bell_Body,
      new List<Object>{ req.Name, details }
    );
  }

  /**
   * @description Builds the company logo for the top of an HTML email. Only https links are used, and the link is
   *   escaped.
   * @return an HTML paragraph with the logo, or '' when there is none
   */
  @TestVisible
  private static String logoHtml() {
    Map<String, String> branding = SignZeroSettings.branding();
    String url = branding.get('logoUrl');
    if (String.isBlank(url) || !url.startsWithIgnoreCase('https://')) {
      return '';
    }
    return '<p><img src="' +
      url.escapeHtml4() +
      '" alt="' +
      branding.get('companyName').escapeHtml4() +
      '" style="max-height:48px;max-width:240px" /></p>';
  }

  /**
   * @description Builds an HTML paragraph from a label. The label and values are escaped, except values already made
   *   safe by strong().
   * @param label the label text, with {0}, {1}... placeholders
   * @param values the values, in order
   * @return the paragraph HTML
   */
  private static String paragraph(String label, List<Object> values) {
    List<Object> escaped = new List<Object>();
    for (Object value : values) {
      escaped.add(
        value instanceof HtmlFragment
          ? ((HtmlFragment) value).html
          : String.valueOf(value).escapeHtml4()
      );
    }
    return '<p>' + String.format(label.escapeHtml4(), escaped) + '</p>';
  }

  /**
   * @description Marks text as bold for paragraph().
   * @param text the text, escaped here
   * @return the bold HTML fragment
   */
  private static HtmlFragment strong(String text) {
    return new HtmlFragment('<strong>' + text.escapeHtml4() + '</strong>');
  }

  /**
   * @description HTML that paragraph() inserts without escaping again.
   */
  private class HtmlFragment {
    final String html;
    HtmlFragment(String html) {
      this.html = html;
    }
  }
}
