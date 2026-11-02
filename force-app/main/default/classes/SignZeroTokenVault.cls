/**
 * @description Encrypts signing tokens so automatic reminders can re-send the link a signer already has. Links are
 *   always checked against the token's hash; the encrypted copy is only decrypted to write a reminder. The AES-256 key
 *   is generated on first use and kept in the protected SignZero_Encryption__c custom setting.
 */
public without sharing class SignZeroTokenVault {
  private static Blob key;

  /**
   * @description Encrypts a signing token.
   * @param rawToken the token sent in the link
   * @return the encrypted token, Base64
   */
  public static String encrypt(String rawToken) {
    return EncodingUtil.base64Encode(
      Crypto.encryptWithManagedIV('AES256', key(), Blob.valueOf(rawToken))
    );
  }

  /**
   * @description Decrypts a token from encrypt() and checks it still matches the link's hash.
   * @param encrypted the encrypted token
   * @param tokenHash the recipient's current Token_Hash__c
   * @return the token, or null when there is none, it cannot be decrypted, or it belongs to an older link
   */
  public static String decrypt(String encrypted, String tokenHash) {
    if (String.isBlank(encrypted) || String.isBlank(tokenHash)) {
      return null;
    }
    try {
      String rawToken = Crypto.decryptWithManagedIV(
          'AES256',
          key(),
          EncodingUtil.base64Decode(encrypted)
        )
        .toString();
      return SignZeroInvitationService.hashToken(rawToken) == tokenHash
        ? rawToken
        : null;
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * @description Hashes a short secret, such as a one-time passcode, with the org's key, so the stored hash cannot be
   *   reversed by trying every possible code.
   * @param value the secret
   * @return HMAC-SHA256 of the value, as lower-case hex
   */
  public static String mac(String value) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac('hmacSHA256', Blob.valueOf(value), key())
    );
  }

  /**
   * @description Returns the org's encryption key, creating it the first time it is needed.
   * @return the AES-256 key
   */
  private static Blob key() {
    if (key != null) {
      return key;
    }
    SignZero_Encryption__c settings = SignZero_Encryption__c.getOrgDefaults();
    if (String.isBlank(settings.Token_Key__c)) {
      settings.Token_Key__c = EncodingUtil.base64Encode(
        Crypto.generateAesKey(256)
      );
      try {
        upsert as system settings;
      } catch (DmlException e) {
        // Another transaction created it first.
        settings = [
          SELECT Token_Key__c
          FROM SignZero_Encryption__c
          WHERE SetupOwnerId = :UserInfo.getOrganizationId()
          WITH SYSTEM_MODE
          LIMIT 1
        ];
      }
    }
    key = EncodingUtil.base64Decode(settings.Token_Key__c);
    return key;
  }
}
