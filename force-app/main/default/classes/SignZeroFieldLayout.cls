/**
 * @description Signature places chosen by the sender on the Place Signatures screen (signZeroFieldPlacer). A layout is
 *   stored on the envelope as JSON and used by the signing page instead of the PDF's {{sig:Role}} tags; the PDF itself
 *   is never changed.
 */
public with sharing class SignZeroFieldLayout {
  /**
   * @description One signature place, in PDF points.
   */
  public class Placement {
    /** @description Signer Role that signs here. */
    @AuraEnabled
    public String role;
    /** @description Page index, from 0. */
    @AuraEnabled
    public Integer page;
    /** @description Left edge of the signature area. */
    @AuraEnabled
    public Decimal x;
    /** @description Bottom edge of the signature area. */
    @AuraEnabled
    public Decimal y;
    /** @description Height of the signature area. */
    @AuraEnabled
    public Decimal height;
  }

  /**
   * @description Loads the PDF for the Place Signatures screen, with the same type and size checks as sending.
   * @param documentId ContentDocument Id of the PDF to send, as text: Flow can pass any text here, and a non-Id
   *   value should be reported rather than rejected before this method runs
   * @return the latest version of the file, Base64 encoded
   */
  @AuraEnabled
  public static String loadDocument(String documentId) {
    Id contentDocumentId;
    try {
      contentDocumentId = Id.valueOf(documentId == null ? '' : documentId.trim());
    } catch (StringException e) {
      throw fail(
        String.format(
          System.Label.SZ_Send_Err_File_Not_Found,
          new List<Object>{ '"' + documentId + '"' }
        )
      );
    }
    List<ContentVersion> versions = [
      SELECT FileType, ContentSize
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH USER_MODE
    ];
    if (versions.isEmpty()) {
      throw fail(
        String.format(
          System.Label.SZ_Send_Err_File_Not_Found,
          new List<Object>{ contentDocumentId }
        )
      );
    }
    if (versions[0].FileType != 'PDF') {
      throw fail(
        String.format(
          System.Label.SZ_Send_Err_Not_Pdf,
          new List<Object>{ versions[0].FileType }
        )
      );
    }
    Integer maxBytes = SignZeroSettings.maxDocumentBytes();
    if (versions[0].ContentSize > maxBytes) {
      throw fail(
        String.format(
          System.Label.SZ_Send_Err_Too_Large,
          new List<Object>{
            String.valueOf(versions[0].ContentSize / 1024),
            String.valueOf(maxBytes / 1024)
          }
        )
      );
    }
    Blob body = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH USER_MODE
      LIMIT 1
    ]
    .VersionData;
    return EncodingUtil.base64Encode(body);
  }

  /**
   * @description Checks a layout before it is stored and writes each role as its Signer Role value.
   * @param layoutJson the layout from the Place Signatures screen; blank means none
   * @param signerRoles the envelope's signer roles
   * @return the layout to store, or null when blank or empty
   */
  public static String normalize(String layoutJson, Set<String> signerRoles) {
    if (String.isBlank(layoutJson)) {
      return null;
    }
    List<Placement> placements;
    try {
      placements = (List<Placement>) JSON.deserializeStrict(
        layoutJson,
        List<Placement>.class
      );
    } catch (JSONException e) {
      throw layoutError('not a list of signature places');
    }
    if (placements == null || placements.isEmpty()) {
      return null;
    }
    if (placements.size() > SignZeroConstants.MAX_FIELD_PLACEMENTS) {
      throw layoutError(
        'more than ' + SignZeroConstants.MAX_FIELD_PLACEMENTS + ' places'
      );
    }
    Map<String, String> roles = new Map<String, String>();
    for (String role : signerRoles) {
      roles.put(role.toLowerCase(), role);
    }
    for (Placement p : placements) {
      if (p == null || p.page == null || p.page < 0 || p.x == null || p.y == null) {
        throw layoutError('a place has no page or position');
      }
      String role = String.isBlank(p.role) ? null : roles.get(p.role.trim().toLowerCase());
      if (role == null) {
        throw new SignZeroSettings.SignZeroException(
          String.format(
            System.Label.SZ_Send_Err_Field_Layout_Role,
            new List<Object>{ p.role }
          )
        );
      }
      p.role = role;
      p.x = p.x.setScale(2);
      p.y = p.y.setScale(2);
      Decimal height = p.height == null
        ? Decimal.valueOf(SignZeroConstants.DEFAULT_SIGNATURE_HEIGHT)
        : p.height.setScale(2);
      p.height = Math.min(
        Decimal.valueOf(SignZeroConstants.MAX_SIGNATURE_HEIGHT),
        Math.max(Decimal.valueOf(SignZeroConstants.MIN_SIGNATURE_HEIGHT), height)
      );
    }
    return JSON.serialize(placements);
  }

  /**
   * @description The places one signer signs at.
   * @param layoutJson the envelope's stored layout
   * @param role the signer's role
   * @return that role's places, or null when the envelope has no layout (the signer's tags are used)
   */
  public static List<Placement> forRole(String layoutJson, String role) {
    if (String.isBlank(layoutJson)) {
      return null;
    }
    List<Placement> own = new List<Placement>();
    for (
      Placement p : (List<Placement>) JSON.deserialize(
        layoutJson,
        List<Placement>.class
      )
    ) {
      if (role != null && p.role.equalsIgnoreCase(role)) {
        own.add(p);
      }
    }
    return own;
  }

  private static SignZeroSettings.SignZeroException layoutError(String problem) {
    return new SignZeroSettings.SignZeroException(
      String.format(
        System.Label.SZ_Send_Err_Field_Layout,
        new List<Object>{ problem }
      )
    );
  }

  private static AuraHandledException fail(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
