/**
 * @description Company branding for the signing site header. Open to the site guest user: it returns only what every
 *   signer sees anyway.
 */
public with sharing class SignZeroBrandingController {
  /**
   * @description Returns the branding for the site header; needs no signing token.
   * @return logoUrl, faviconUrl, companyName, primaryColor, primaryHoverColor and accentColor
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, String> getBranding() {
    return SignZeroSettings.branding();
  }
}
