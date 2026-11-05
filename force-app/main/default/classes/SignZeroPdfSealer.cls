/**
 * @description Seals a PDF with a PAdES digital signature (baseline B-B, ETSI.CAdES.detached), so PDF readers can show
 *   that it has not changed since sealing and who sealed it. The private key stays in Salesforce: an org certificate
 *   signs through Crypto.signWithCertificate. Apex has no CMS library, so the signature's DER is built here, as hex.
 */
public inherited sharing class SignZeroPdfSealer {
  // DER of the object identifiers used in the signature.
  private static final String OID_DATA = '06092a864886f70d010701';
  private static final String OID_SIGNED_DATA = '06092a864886f70d010702';
  private static final String OID_CONTENT_TYPE = '06092a864886f70d010903';
  private static final String OID_MESSAGE_DIGEST = '06092a864886f70d010904';
  private static final String OID_SIGNING_CERTIFICATE_V2 = '060b2a864886f70d010910022f';
  private static final String OID_SHA256_WITH_RSA = '06092a864886f70d01010b';
  private static final String OID_SHA256 = '0609608648016503040201';
  private static final String DER_NULL = '0500';

  private static final String TAG_SEQUENCE = '30';
  private static final String TAG_SET = '31';
  private static final String TAG_OCTET_STRING = '04';
  private static final String TAG_CONTEXT_0 = 'a0';
  private static final String INTEGER_1 = '020101';

  private static final String HEX_DIGITS = '0123456789abcdef';

  /** @description Replaces the signature in tests, where the org has no certificate to sign with. */
  @TestVisible
  private static Blob signatureInTest;

  /**
   * @description Seals a PDF as an incremental update, so its earlier bytes stay as they were.
   * @param pdf the PDF to seal, with classic cross-reference tables
   * @param certificateName API name of the org certificate that signs
   * @param certificateDer that certificate's public part, as DER
   * @param sealedBy the name shown with the seal
   * @param reason why it was sealed
   * @return the sealed PDF
   */
  public static Blob seal(
    Blob pdf,
    String certificateName,
    Blob certificateDer,
    String sealedBy,
    String reason
  ) {
    SignZeroPdfAppender.PreparedSignature prepared = SignZeroPdfAppender.prepareSignature(
      pdf,
      SignZeroConstants.MAX_SEAL_BYTES,
      sealedBy,
      reason
    );
    String cms = buildCms(
      Crypto.generateDigest('SHA-256', prepared.signedBytes()),
      certificateName,
      EncodingUtil.convertToHex(certificateDer)
    );
    return prepared.withSignature(cms);
  }

  /**
   * @description Signs with an org certificate.
   * @param input the bytes to sign
   * @param certificateName API name of the org certificate
   * @return the RSA-SHA256 signature
   */
  public static Blob sign(Blob input, String certificateName) {
    return signatureInTest != null
      ? signatureInTest
      : Crypto.signWithCertificate('RSA-SHA256', input, certificateName);
  }

  /**
   * @description Builds the detached CMS SignedData for a document digest.
   * @param digest SHA-256 of the signed bytes
   * @param certificateName API name of the org certificate that signs
   * @param certificate the certificate's DER, as hex
   * @return the SignedData's DER, as hex
   */
  private static String buildCms(
    Blob digest,
    String certificateName,
    String certificate
  ) {
    String sha256 = der(TAG_SEQUENCE, OID_SHA256 + DER_NULL);

    // Signed attributes. PAdES forbids signing-time here; the time is in the signature dictionary's /M.
    String certHash = EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        EncodingUtil.convertFromHex(certificate)
      )
    );
    // ESSCertIDv2 with the default hash algorithm, SHA-256.
    String signingCertificate = der(
      TAG_SEQUENCE,
      der(TAG_SEQUENCE, der(TAG_SEQUENCE, der(TAG_OCTET_STRING, certHash)))
    );
    List<String> attributes = new List<String>{
      attribute(OID_CONTENT_TYPE, OID_DATA),
      attribute(
        OID_MESSAGE_DIGEST,
        der(TAG_OCTET_STRING, EncodingUtil.convertToHex(digest))
      ),
      attribute(OID_SIGNING_CERTIFICATE_V2, signingCertificate)
    };
    // DER orders a SET by its encoded members.
    attributes.sort();
    String attributeBytes = String.join(attributes, '');

    // The signature covers the attributes encoded as a SET, though they are stored with a context tag.
    Blob signature = sign(
      EncodingUtil.convertFromHex(der(TAG_SET, attributeBytes)),
      certificateName
    );

    String signerInfo = der(
      TAG_SEQUENCE,
      INTEGER_1 +
        issuerAndSerial(certificate) +
        sha256 +
        der(TAG_CONTEXT_0, attributeBytes) +
        der(TAG_SEQUENCE, OID_SHA256_WITH_RSA + DER_NULL) +
        der(TAG_OCTET_STRING, EncodingUtil.convertToHex(signature))
    );
    String signedData = der(
      TAG_SEQUENCE,
      INTEGER_1 +
        der(TAG_SET, sha256) +
        der(TAG_SEQUENCE, OID_DATA) +
        der(TAG_CONTEXT_0, certificate) +
        der(TAG_SET, signerInfo)
    );
    return der(
      TAG_SEQUENCE,
      OID_SIGNED_DATA + der(TAG_CONTEXT_0, signedData)
    );
  }

  private static String attribute(String oid, String value) {
    return der(TAG_SEQUENCE, oid + der(TAG_SET, value));
  }

  /**
   * @description Reads who issued a certificate and its serial number, which identify the signer in the CMS.
   * @param certificate the certificate's DER, as hex
   * @return the IssuerAndSerialNumber's DER, as hex
   */
  private static String issuerAndSerial(String certificate) {
    Integer[] whole = element(certificate, 0);
    Integer[] tbs = element(certificate, whole[0]);
    Integer position = tbs[0];
    if (certificate.substring(position, position + 2) == TAG_CONTEXT_0) {
      position = element(certificate, position)[1]; // the optional version
    }
    Integer[] serial = element(certificate, position);
    Integer[] algorithm = element(certificate, serial[1]);
    Integer[] issuer = element(certificate, algorithm[1]);
    return der(
      TAG_SEQUENCE,
      certificate.substring(algorithm[1], issuer[1]) +
      certificate.substring(position, serial[1])
    );
  }

  /**
   * @description Reads the DER element at a position.
   * @param hex DER, as hex
   * @param position index of the element's tag in hex
   * @return [index of its content, index after it]
   */
  private static Integer[] element(String hex, Integer position) {
    Integer length = byteAt(hex, position + 2);
    Integer content = position + 4;
    if (length >= 128) {
      Integer lengthBytes = length - 128;
      length = 0;
      for (Integer i = 0; i < lengthBytes; i++) {
        length = length * 256 + byteAt(hex, content);
        content += 2;
      }
    }
    return new List<Integer>{ content, content + length * 2 };
  }

  private static Integer byteAt(String hex, Integer position) {
    return HEX_DIGITS.indexOf(hex.substring(position, position + 1)) * 16 +
      HEX_DIGITS.indexOf(hex.substring(position + 1, position + 2));
  }

  /**
   * @description Encodes a DER element.
   * @param tag its tag, as hex
   * @param content its content, as hex
   * @return tag, length and content, as hex
   */
  private static String der(String tag, String content) {
    Integer size = content.length() / 2;
    String length;
    if (size < 128) {
      length = byteHex(size);
    } else if (size < 256) {
      length = '81' + byteHex(size);
    } else if (size < 65536) {
      length = '82' + byteHex(size / 256) + byteHex(Math.mod(size, 256));
    } else {
      length =
        '83' +
        byteHex(size / 65536) +
        byteHex(Math.mod(size / 256, 256)) +
        byteHex(Math.mod(size, 256));
    }
    return tag + length + content;
  }

  private static String byteHex(Integer value) {
    return HEX_DIGITS.substring(value / 16, value / 16 + 1) +
      HEX_DIGITS.substring(Math.mod(value, 16), Math.mod(value, 16) + 1);
  }
}
