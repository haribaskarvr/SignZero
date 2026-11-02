/**
 * @description Builds SignZero's signer emails from Salesforce email templates that admins can edit. Each
 *   SignZero_Email_Template__mdt record names the template for one email; SignZero ships defaults in the SignZero
 *   Emails folder. The template's subject, HTML and text are read as they are and SignZero's [[Name]] placeholders are
 *   filled in by string replacement, so the template needs no merge fields and works for the site guest user too. A
 *   blank setting, a missing template or one without its required placeholder falls back to the built-in email.
 */
public without sharing class SignZeroEmailTemplates {
  /** @description Email type to template unique name, from SignZero_Email_Template__mdt; tests set it directly. */
  @TestVisible
  private static Map<String, String> templateNames;
  private static Map<String, EmailTemplate> templates;

  /**
   * @description Fills an email's subject and bodies from the template set for this email type.
   * @param mail the email to fill; left untouched when the built-in email should be used
   * @param emailType an EMAIL_* type from SignZeroConstants
   * @param values placeholder name (without brackets) to value
   * @return true when the template was used; false to build the built-in email
   */
  public static Boolean apply(
    Messaging.SingleEmailMessage mail,
    String emailType,
    Map<String, String> values
  ) {
    EmailTemplate template = template(emailType);
    if (template == null) {
      return false;
    }
    String html = String.isBlank(template.HtmlValue) ? null : template.HtmlValue;
    String text = String.isBlank(template.Body) ? null : template.Body;
    if (html == null && text == null) {
      warn(emailType, template.DeveloperName + ' is empty');
      return false;
    }
    String required = SignZeroConstants.EMAIL_REQUIRED_PLACEHOLDER.get(emailType);
    if (
      required != null &&
      !(html != null && html.contains(token(required))) &&
      !(text != null && text.contains(token(required)))
    ) {
      warn(emailType, template.DeveloperName + ' has no ' + token(required));
      return false;
    }
    mail.setSubject(fill(template.Subject, values, false));
    if (html != null) {
      mail.setHtmlBody(fill(html, values, true));
    }
    if (text != null) {
      mail.setPlainTextBody(fill(text, values, false));
    }
    return true;
  }

  /**
   * @description Replaces each [[Name]] placeholder; unknown placeholders are left as they are. [[Logo]] is HTML
   *   SignZero builds itself, so it goes into HTML unescaped and is left out of plain text.
   * @param body the template's subject or body
   * @param values placeholder name to value
   * @param html true to escape the values for HTML
   * @return the filled text
   */
  @TestVisible
  private static String fill(String body, Map<String, String> values, Boolean html) {
    if (body == null) {
      return null;
    }
    for (String name : values.keySet()) {
      String value = values.get(name) == null ? '' : values.get(name);
      if (name == SignZeroConstants.PLACEHOLDER_LOGO) {
        value = html ? value : '';
      } else if (html) {
        value = value.escapeHtml4();
      }
      body = body.replace(token(name), value);
    }
    return body;
  }

  /**
   * @description Writes a placeholder as it appears in a template. Square brackets, because Lightning templates read
   *   {{...}} as their own merge syntax and reject names they do not know.
   * @param name the placeholder name
   * @return e.g. [[SigningLink]]
   */
  private static String token(String name) {
    return '[[' + name + ']]';
  }

  /**
   * @description Finds the active template set for an email type, looking all of them up once per transaction.
   * @param emailType an EMAIL_* type from SignZeroConstants
   * @return the template, or null to use the built-in email
   */
  private static EmailTemplate template(String emailType) {
    if (templates == null) {
      templates = new Map<String, EmailTemplate>();
      Map<String, String> names = configuredNames();
      if (!names.isEmpty()) {
        Map<String, EmailTemplate> byName = new Map<String, EmailTemplate>();
        for (EmailTemplate t : [
          SELECT DeveloperName, Subject, HtmlValue, Body
          FROM EmailTemplate
          WHERE DeveloperName IN :names.values() AND IsActive = TRUE
          WITH SYSTEM_MODE
        ]) {
          byName.put(t.DeveloperName, t);
        }
        for (String type : names.keySet()) {
          EmailTemplate found = byName.get(names.get(type));
          if (found == null) {
            warn(type, names.get(type) + ' is not an active email template');
          } else {
            templates.put(type, found);
          }
        }
      }
    }
    return templates.get(emailType);
  }

  /**
   * @description Reads the template names set in SignZero_Email_Template__mdt.
   * @return email type to template unique name, for the types that have one
   */
  private static Map<String, String> configuredNames() {
    if (templateNames == null) {
      templateNames = new Map<String, String>();
      for (SignZero_Email_Template__mdt row : SignZero_Email_Template__mdt.getAll().values()) {
        if (String.isNotBlank(row.Template_Name__c)) {
          templateNames.put(row.DeveloperName, row.Template_Name__c.trim());
        }
      }
    }
    return templateNames;
  }

  private static void warn(String emailType, String problem) {
    System.debug(
      LoggingLevel.WARN,
      'SignZero ' + emailType + ' email template: ' + problem + '; the built-in email is used'
    );
  }
}
