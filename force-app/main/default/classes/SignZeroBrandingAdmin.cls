/**
 * @description Backs the SignZero Header's Logo and Favicon editors in Experience Builder. Stores an uploaded image as
 *   a public Salesforce File and saves its link in the SignZero Branding custom setting. Admins only: the site guest
 *   user has no access.
 */
public with sharing class SignZeroBrandingAdmin {
  /**
   * @description How each kind of image is stored, and which branding field holds its link.
   */
  private class ImageKind {
    final String title;
    final Set<String> extensions;
    final Schema.SObjectField field;
    final String typeError;
    ImageKind(String title, Set<String> extensions, Schema.SObjectField field, String typeError) {
      this.title = title;
      this.extensions = extensions;
      this.field = field;
      this.typeError = typeError;
    }
  }

  /**
   * @description Stores an uploaded image as a public Salesforce File and makes it the logo or favicon.
   * @param kind logo or favicon
   * @param fileName the uploaded file's name, used for its extension
   * @param base64Data the file's contents, Base64 (up to 1 MB)
   * @return the image's public URL
   */
  @AuraEnabled
  public static String saveImage(String kind, String fileName, String base64Data) {
    ImageKind image = kindOf(kind);
    requireAccess();
    String extension = String.isBlank(fileName)
      ? ''
      : fileName.substringAfterLast('.').toLowerCase();
    if (!image.extensions.contains(extension)) {
      throw fail(image.typeError);
    }
    Blob data = String.isBlank(base64Data)
      ? Blob.valueOf('')
      : EncodingUtil.base64Decode(base64Data);
    if (data.size() == 0 || data.size() > SignZeroConstants.MAX_IMAGE_BYTES) {
      throw fail(System.Label.SZ_Image_Err_Size);
    }
    try {
      ContentVersion version = new ContentVersion(
        Title = image.title,
        PathOnClient = image.title + '.' + extension,
        VersionData = data
      );
      insert as user version;
      // No password or expiry, so signers and email clients load it without a login.
      ContentDistribution link = new ContentDistribution(
        Name = image.title,
        ContentVersionId = version.Id,
        PreferencesAllowViewInBrowser = true,
        PreferencesLinkLatestVersion = true,
        PreferencesNotifyOnVisit = false,
        PreferencesPasswordRequired = false,
        PreferencesAllowOriginalDownload = true
      );
      insert as user link;
      String url = [
        SELECT ContentDownloadUrl
        FROM ContentDistribution
        WHERE Id = :link.Id
        WITH USER_MODE
      ]
      .ContentDownloadUrl;
      setImage(image, url);
      return url;
    } catch (Exception e) {
      throw saveFailed(e);
    }
  }

  /**
   * @description Clears the logo or favicon. Without a favicon, the logo is used in the browser tab.
   * @param kind logo or favicon
   */
  @AuraEnabled
  public static void removeImage(String kind) {
    ImageKind image = kindOf(kind);
    requireAccess();
    try {
      setImage(image, null);
    } catch (Exception e) {
      throw saveFailed(e);
    }
  }

  /**
   * @description Saves an image link in the SignZero Branding org default.
   * @param image the kind of image
   * @param url the public link, or null to clear it
   */
  private static void setImage(ImageKind image, String url) {
    SignZero_Branding__c branding = SignZeroSettings.orgBranding();
    branding.put(image.field, url);
    upsert as system branding;
  }

  /**
   * @description Throws unless the user can edit SignZero Branding, the same right as editing the custom setting in
   *   Setup.
   */
  private static void requireAccess() {
    if (
      !Schema.SObjectType.SignZero_Branding__c.isCreateable() ||
      !Schema.SObjectType.SignZero_Branding__c.isUpdateable()
    ) {
      throw fail(System.Label.SZ_Image_Err_No_Access);
    }
  }

  /**
   * @description Looks up how a kind of image is stored.
   * @param kind logo or favicon
   * @return the image kind; throws for anything else
   */
  private static ImageKind kindOf(String kind) {
    if (kind == SignZeroConstants.IMAGE_LOGO) {
      return new ImageKind(
        SignZeroConstants.LOGO_TITLE,
        SignZeroConstants.LOGO_EXTENSIONS,
        SignZero_Branding__c.Logo_Url__c,
        System.Label.SZ_Logo_Err_Type
      );
    }
    if (kind == SignZeroConstants.IMAGE_FAVICON) {
      return new ImageKind(
        SignZeroConstants.FAVICON_TITLE,
        SignZeroConstants.FAVICON_EXTENSIONS,
        SignZero_Branding__c.Favicon_Url__c,
        System.Label.SZ_Favicon_Err_Type
      );
    }
    throw fail('Unknown image kind: ' + kind);
  }

  /**
   * @description Builds the error shown when an image cannot be stored or saved.
   * @param e what went wrong
   * @return the exception to throw
   */
  @TestVisible
  private static AuraHandledException saveFailed(Exception e) {
    return fail(
      String.format(
        System.Label.SZ_Image_Err_Save,
        new List<Object>{ e.getMessage() }
      )
    );
  }

  /**
   * @description Builds an error the editor shows as is.
   * @param message the message for the admin
   * @return the exception to throw
   */
  private static AuraHandledException fail(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
