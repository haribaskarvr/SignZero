/**
 * @description Reads SignZero Settings (the Default SignZero_Setting__mdt record) and the SignZero Branding custom
 *   setting, with defaults for blank fields.
 */
public inherited sharing class SignZeroSettings {
  @TestVisible
  private static SignZero_Setting__mdt cached;

  /**
   * @description Returns the Default settings record, cached for the transaction.
   * @return the record, or an empty one when it does not exist
   */
  public static SignZero_Setting__mdt get() {
    if (cached == null) {
      cached = SignZero_Setting__mdt.getInstance(SignZeroConstants.SETTINGS_RECORD);
      if (cached == null) {
        cached = new SignZero_Setting__mdt(DeveloperName = SignZeroConstants.SETTINGS_RECORD);
      }
    }
    return cached;
  }

  /**
   * @description Whether signers may delegate their signature.
   * @return true unless the setting is switched off
   */
  public static Boolean allowReassignment() {
    return get().Allow_Reassignment__c != false;
  }

  /**
   * @description Whether a signer with no tag and no place from the sender drags their signature onto the document.
   * @return true unless Allow Signer Placement is off
   */
  public static Boolean allowSignerPlacement() {
    return get().Allow_Signer_Placement__c != false;
  }

  /**
   * @description Whether signers must accept the electronic record disclosure before the document is shown.
   * @return true only when the setting is on; by default signers read first and consent when they sign
   */
  public static Boolean requireConsentBeforeViewing() {
    return get().Require_Consent_Before_Viewing__c == true;
  }

  /**
   * @description Whether the signing page logs step timings.
   * @return the SignZero_Diagnostics__c Performance Logs value for the running user
   */
  public static Boolean performanceLogs() {
    SignZero_Diagnostics__c diagnostics = SignZero_Diagnostics__c.getInstance();
    return diagnostics != null && diagnostics.Performance_Logs__c == true;
  }

  /**
   * @description Version (last deploy time) of the signZeroPdfHost static resource, so the portal can reload a stale
   *   cached copy.
   * @return the version, or null when the resource is missing
   */
  public static Long pdfHostVersion() {
    List<StaticResource> host = [
      SELECT SystemModstamp
      FROM StaticResource
      WHERE Name = :SignZeroConstants.PDF_HOST_RESOURCE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return host.isEmpty() ? null : host[0].SystemModstamp.getTime();
  }

  /**
   * @description How long a signing link works.
   * @return days; 7 when not set
   */
  public static Integer tokenValidityDays() {
    Decimal days = get().Token_Validity_Days__c;
    return days == null || days <= 0
      ? SignZeroConstants.DEFAULT_TOKEN_VALIDITY_DAYS
      : days.intValue();
  }

  /**
   * @description Days without a signature before the first automatic reminder.
   * @return days, or null when reminders are off
   */
  public static Integer reminderFirstAfterDays() {
    Decimal days = get().Reminder_First_After_Days__c;
    return days == null || days <= 0 ? null : days.intValue();
  }

  /**
   * @description Days between later reminders.
   * @return days, or null to send only one reminder
   */
  public static Integer reminderRepeatDays() {
    Decimal days = get().Reminder_Repeat_Days__c;
    return days == null || days <= 0 ? null : days.intValue();
  }

  /**
   * @description Most reminders a signer gets for one invitation.
   * @return the limit; 3 when not set, 1 when reminders do not repeat
   */
  public static Integer reminderLimit() {
    if (reminderRepeatDays() == null) {
      return 1;
    }
    Decimal limitValue = get().Reminder_Limit__c;
    return limitValue == null || limitValue <= 0
      ? SignZeroConstants.DEFAULT_REMINDER_LIMIT
      : limitValue.intValue();
  }

  /**
   * @description When the reminder job runs (Reminder Schedule).
   * @return a Salesforce cron expression; "0 0 9 * * ?" (daily at 9:00) when not set
   */
  public static String reminderCronExpression() {
    String cron = get().Reminder_Schedule__c;
    return String.isBlank(cron)
      ? SignZeroConstants.DEFAULT_REMINDER_SCHEDULE
      : cron.trim();
  }

  /**
   * @description Largest PDF accepted.
   * @return bytes; 2000 KB when not set
   */
  public static Integer maxDocumentBytes() {
    Decimal kb = get().Max_Document_Size_KB__c;
    return (kb == null || kb <= 0 ? SignZeroConstants.DEFAULT_MAX_DOCUMENT_KB : kb.intValue()) * 1024;
  }

  /**
   * @description Returns the values set in this org rather than deployed: logo, favicon and org-wide email address.
   *   Deployments never overwrite them.
   * @return the SignZero_Branding__c org default; fields are blank when nothing is set
   */
  public static SignZero_Branding__c orgBranding() {
    return SignZero_Branding__c.getOrgDefaults();
  }

  /**
   * @description Returns the org-wide address SignZero emails are sent from.
   * @return the address, or null to send from each sender's own address
   */
  public static String orgWideEmailAddress() {
    return orgBranding().Org_Wide_Email_Address__c;
  }

  /**
   * @description Returns the branding for the signing page and emails. Colours that are not #rgb or #rrggbb are
   *   dropped.
   * @return logoUrl, faviconUrl, companyName, primaryColor, primaryHoverColor and accentColor
   */
  public static Map<String, String> branding() {
    SignZero_Setting__mdt s = get();
    return new Map<String, String>{
      'logoUrl' => orgBranding().Logo_Url__c,
      'faviconUrl' => orgBranding().Favicon_Url__c,
      'companyName' => String.isBlank(s.Company_Name__c)
        ? 'SignZero'
        : s.Company_Name__c,
      // Blank colours let the site theme apply.
      'primaryColor' => safeColor(s.Primary_Color__c),
      'primaryHoverColor' => safeColor(s.Primary_Hover_Color__c),
      'accentColor' => safeColor(s.Accent_Color__c)
    };
  }

  /**
   * @description Returns the public signing page's base URL: the setting when present, otherwise the site published
   *   under /esign.
   * @return the URL without a trailing slash
   */
  public static String signingBaseUrl() {
    String configured = get().Site_Base_Url__c;
    if (String.isNotBlank(configured)) {
      return configured.removeEnd('/');
    }
    List<DomainSite> sites = [
      SELECT Domain.Domain, PathPrefix
      FROM DomainSite
      WHERE PathPrefix = '/esign'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (sites.isEmpty()) {
      throw new SignZeroException(System.Label.SZ_Err_Site_Not_Found);
    }
    return 'https://' + sites[0].Domain.Domain + sites[0].PathPrefix;
  }

  /**
   * @description Keeps only #rgb or #rrggbb colours, so branding values cannot inject CSS.
   * @param value a colour from settings
   * @return the colour, or null when it is not a hex colour
   */
  private static String safeColor(String value) {
    return value != null &&
      Pattern.matches('#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})', value)
      ? value
      : null;
  }

  /**
   * @description A SignZero problem with a message meant for the sender.
   */
  public class SignZeroException extends Exception {
  }
}
