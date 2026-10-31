/**
 * Reads the SignZero_Setting__mdt record named "Default" and fills in safe defaults.
 */
public inherited sharing class SignZeroSettings {
  @TestVisible
  private static SignZero_Setting__mdt cached;

  /**
   * The Default settings record, cached for the transaction.
   * @return the record, or an empty one when it does not exist
   */
  public static SignZero_Setting__mdt get() {
    if (cached == null) {
      cached = SignZero_Setting__mdt.getInstance('Default');
      if (cached == null) {
        cached = new SignZero_Setting__mdt(DeveloperName = 'Default');
      }
    }
    return cached;
  }

  /**
   * Whether signers may delegate their signature.
   * @return true unless the setting is switched off
   */
  public static Boolean allowReassignment() {
    return get().Allow_Reassignment__c != false;
  }

  /**
   * Whether the signing page logs step timings.
   * @return the SignZero_Diagnostics__c Performance Logs value for the running user
   */
  public static Boolean performanceLogs() {
    SignZero_Diagnostics__c diagnostics = SignZero_Diagnostics__c.getInstance();
    return diagnostics != null && diagnostics.Performance_Logs__c == true;
  }

  /**
   * Version (last deploy time) of the signZeroPdfHost static resource. The signing portal compares it with the
   * version of the host page it loaded: browsers keep site resources for weeks, so a copy cached before a deploy is
   * reloaded at the versioned URL.
   * @return the version, or null when the resource is missing
   */
  public static Long pdfHostVersion() {
    List<StaticResource> host = [
      SELECT SystemModstamp
      FROM StaticResource
      WHERE Name = 'signZeroPdfHost'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return host.isEmpty() ? null : host[0].SystemModstamp.getTime();
  }

  /**
   * How long a signing link works.
   * @return days, 7 when not set
   */
  public static Integer tokenValidityDays() {
    Decimal days = get().Token_Validity_Days__c;
    return days == null || days <= 0 ? 7 : days.intValue();
  }

  /**
   * Largest PDF accepted.
   * @return bytes, 2000 KB when not set
   */
  public static Integer maxDocumentBytes() {
    Decimal kb = get().Max_Document_Size_KB__c;
    return (kb == null || kb <= 0 ? 2000 : kb.intValue()) * 1024;
  }

  /**
   * Branding for the signing page and emails. Colours that are not #rgb or #rrggbb are dropped.
   * @return logoUrl, companyName, primaryColor, primaryHoverColor and accentColor
   */
  public static Map<String, String> branding() {
    SignZero_Setting__mdt s = get();
    return new Map<String, String>{
      'logoUrl' => s.Logo_Url__c,
      'companyName' => String.isBlank(s.Company_Name__c)
        ? 'SignZero'
        : s.Company_Name__c,
      // Blank colours let the signing site's theme branding apply.
      'primaryColor' => safeColor(s.Primary_Color__c),
      'primaryHoverColor' => safeColor(s.Primary_Hover_Color__c),
      'accentColor' => safeColor(s.Accent_Color__c)
    };
  }

  /**
   * Base URL of the public signing page. Uses the setting when present, otherwise
   * looks for a site published under the /esign path prefix.
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

  // Only allow #rgb / #rrggbb so branding values cannot inject CSS.
  private static String safeColor(String value) {
    return value != null &&
      Pattern.matches('#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})', value)
      ? value
      : null;
  }

  /** A SignZero problem with a message meant for the sender. */
  public class SignZeroException extends Exception {
  }
}
