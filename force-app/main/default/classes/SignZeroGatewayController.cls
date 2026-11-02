/**
 * @description The only Apex the public signing site can call. Runs without sharing and authorises every call by the
 *   SHA-256 hash of the signer's token; the site guest user has no object permissions.
 */
public without sharing class SignZeroGatewayController {
  /**
   * @description Opens the signing page. Signers who already signed can reopen their link read-only until it expires.
   * @param rawToken the token from the signing link
   * @param userAgent the signer's browser, for the audit trail
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   * @return the document (Base64), signer and envelope details, settings and branding. With Require Consent Before
   *   Viewing on and no consent yet, the document is left out and consentBeforeViewing is true. When the signer must
   *   still enter a passcode, only passcodeRequired, where the code goes and branding are returned.
   */
  @AuraEnabled
  public static Map<String, Object> initializeSession(
    String rawToken,
    String userAgent,
    String passcodeSession
  ) {
    SignZero_Recipient__c recipient = findOpenableRecipient(rawToken);
    String envelopeStatus = recipient.SignZero_Request__r.Status__c;
    Boolean readOnly = !isSignable(recipient);
    if (!passcodeVerified(recipient, passcodeSession)) {
      // Nothing about the document leaves Salesforce until the signer enters the code emailed to them.
      return passcodeChallenge(recipient);
    }
    // Consent first: no part of the document leaves Salesforce until the signer accepts the disclosure.
    Boolean consentFirst =
      !readOnly &&
      recipient.Consented_At__c == null &&
      SignZeroSettings.requireConsentBeforeViewing();
    Blob pdf;
    if (!consentFirst) {
      // The guest user cannot read Files, so signers get the envelope's Attachment copy.
      Id workingCopyId = recipient.SignZero_Request__r.Working_Copy_Id__c;
      Attachment shown = [
        SELECT Id, BodyLength
        FROM Attachment
        WHERE Id = :workingCopyId
        WITH SYSTEM_MODE
      ];
      if (shown.BodyLength > SignZeroSettings.maxDocumentBytes()) {
        throw fail(System.Label.SZ_Err_Too_Large);
      }
      pdf = [
        SELECT Body
        FROM Attachment
        WHERE Id = :shown.Id
        WITH SYSTEM_MODE
      ]
      .Body;
    }

    String ip = SignZeroAuditService.clientIp();
    if (!readOnly) {
      if (!consentFirst) {
        if (recipient.Status__c == SignZeroConstants.SIGNER_SENT) {
          recipient.Status__c = SignZeroConstants.SIGNER_VIEWED;
        }
        // With consent first, the signer is already Consented at the first view.
        if (recipient.Viewed_At__c == null) {
          recipient.Viewed_At__c = Datetime.now();
        }
      }
      recipient.Last_Known_IP__c = ip;
      recipient.User_Agent__c = clip(userAgent);
      update as system recipient;
    }
    if (!consentFirst) {
      SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
        recipient.Id,
        recipient.SignZero_Request__c,
        SignZeroConstants.EVENT_VIEWED
      );
      e.ipAddress = ip;
      e.userAgent = userAgent;
      e.documentHash = recipient.SignZero_Request__r.Working_Copy_Hash__c;
      e.details = readOnly ? 'Read-only view after signing' : null;
      SignZeroAuditService.logOne(e);
    }

    Integer othersToSign = [
      SELECT COUNT()
      FROM SignZero_Recipient__c
      WHERE
        SignZero_Request__c = :recipient.SignZero_Request__c
        AND Id != :recipient.Id
        AND Status__c IN :SignZeroConstants.SIGNER_AWAITING
      WITH SYSTEM_MODE
    ];

    return new Map<String, Object>{
      'recipientName' => recipient.Name,
      'signerRole' => recipient.Signer_Role__c,
      'documentName' => recipient.SignZero_Request__r.Document_Name__c,
      'envelopeNumber' => recipient.SignZero_Request__r.Name,
      'consentAccepted' => recipient.Consented_At__c != null,
      'readOnly' => readOnly,
      'envelopeStatus' => envelopeStatus,
      'signedAt' => recipient.Signed_At__c,
      // The last signer also clears leftover anchor tags from the document text.
      'isLastSigner' => othersToSign == 0,
      'allowReassign' => !readOnly && SignZeroSettings.allowReassignment(),
      // A signer with no tag and no place from the sender places their own signature.
      'allowSignerPlacement' => SignZeroSettings.allowSignerPlacement(),
      'performanceLogs' => SignZeroSettings.performanceLogs(),
      'pdfHostVersion' => SignZeroSettings.pdfHostVersion(),
      'consentBeforeViewing' => consentFirst,
      'pdfBase64' => pdf == null ? null : EncodingUtil.base64Encode(pdf),
      // Places chosen by the sender replace the signer's tags; null when the envelope has none.
      'placements' => SignZeroFieldLayout.forRole(
        recipient.SignZero_Request__r.Field_Layout__c,
        recipient.Signer_Role__c
      ),
      'branding' => SignZeroSettings.branding()
    };
  }

  /**
   * @description Records that the signer accepted the ESIGN/UETA disclosure. Accepting again does nothing.
   * @param rawToken the token from the signing link
   * @param userAgent the signer's browser, for the audit trail
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   */
  @AuraEnabled
  public static void recordConsent(
    String rawToken,
    String userAgent,
    String passcodeSession
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken, passcodeSession);
    if (recipient.Consented_At__c != null) {
      return;
    }
    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = SignZeroConstants.SIGNER_CONSENTED;
    recipient.Consented_At__c = Datetime.now();
    recipient.Last_Known_IP__c = ip;
    update as system recipient;
    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      SignZeroConstants.EVENT_CONSENT_ACCEPTED
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = 'Accepted ESIGN/UETA electronic record and signature disclosure';
    SignZeroAuditService.logOne(e);
  }

  /**
   * @description Stores the signer's signed copy, marks them Signed and lets the envelope move on.
   * @param rawToken the token from the signing link
   * @param executedPdfBase64 the PDF the signer was shown, with their signature stamped in by the browser
   * @param signatureImageBase64 PNG of a typed or drawn signature, kept as separate evidence; uploaded images exist
   *   only inside the signed PDF
   * @param signatureMethod Typed, Drawn or Uploaded
   * @param userAgent the signer's browser, for the audit trail
   * @param signerPlacements where the signer chose to put their signature, as JSON [{page, x, y}] in PDF points;
   *   blank when they signed at tags or places set by the sender
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   * @return isFinalSigner: true when this signature completes the envelope
   */
  @AuraEnabled
  public static Map<String, Object> submitExecutedDocument(
    String rawToken,
    String executedPdfBase64,
    String signatureImageBase64,
    String signatureMethod,
    String userAgent,
    String signerPlacements,
    String passcodeSession
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken, passcodeSession);
    if (recipient.Consented_At__c == null) {
      throw fail(System.Label.SZ_Err_Consent_Required);
    }
    String adoption = SignZeroConstants.METHOD_DESCRIPTIONS.get(signatureMethod);
    if (adoption == null) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    String placedAt = describePlacements(signerPlacements);
    if (placedAt != null) {
      adoption += SignZeroConstants.PLACED_BY_SIGNER;
    }
    // "%PDF-" in base64.
    if (
      String.isBlank(executedPdfBase64) ||
      !executedPdfBase64.startsWith('JVBERi0')
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Pdf);
    }
    Blob executed = EncodingUtil.base64Decode(executedPdfBase64);
    executedPdfBase64 = null; // free the heap
    // Headroom for the stamped signature images.
    if (executed.size() > SignZeroSettings.maxDocumentBytes() + 512 * 1024) {
      throw fail(System.Label.SZ_Err_Too_Large);
    }
    String executedHash = SignZeroSealService.computeSHA256Hash(executed);
    if (executedHash == recipient.SignZero_Request__r.Working_Copy_Hash__c) {
      throw fail(System.Label.SZ_Err_No_Signature);
    }

    String ip = SignZeroAuditService.clientIp();
    SignZero_Request__c envelope = recipient.SignZero_Request__r;
    Attachment signedCopy = new Attachment(
      ParentId = envelope.Id,
      Name = (envelope.Document_Name__c +
          ' - signed by ' +
          recipient.Name)
          .left(251) + '.pdf',
      ContentType = SignZeroConstants.PDF_CONTENT_TYPE,
      Body = executed
    );
    List<Attachment> files = new List<Attachment>{ signedCopy };
    if (
      String.isNotBlank(signatureImageBase64) && signatureMethod != SignZeroConstants.METHOD_UPLOADED
    ) {
      files.add(
        new Attachment(
          ParentId = envelope.Id,
          Name = ('Signature image - ' + recipient.Name).left(251) + '.png',
          ContentType = 'image/png',
          Body = EncodingUtil.base64Decode(signatureImageBase64)
        )
      );
    }
    insert as system files;

    recipient.Status__c = SignZeroConstants.SIGNER_SIGNED;
    recipient.Signature_Method__c = adoption;
    recipient.Signed_At__c = Datetime.now();
    recipient.Last_Known_IP__c = ip;
    recipient.User_Agent__c = clip(userAgent);
    // The link can no longer sign, but stays valid for read-only viewing.
    recipient.Token_Expires_At__c = Datetime.now()
      .addDays(SignZeroSettings.tokenValidityDays());
    // No reminders follow, so the encrypted token is no longer needed.
    recipient.Token_Encrypted__c = null;
    update as system recipient;
    update as system new SignZero_Request__c(
      Id = envelope.Id,
      Working_Copy_Id__c = signedCopy.Id,
      Working_Copy_Hash__c = executedHash
    );

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      envelope.Id,
      SignZeroConstants.EVENT_SIGNED
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.documentHash = executedHash;
    e.details =
      'Signed as ' +
      recipient.Signer_Role__c +
      '; signature ' +
      adoption.toLowerCase() +
      (placedAt == null ? '' : '; signer chose the places: ' + placedAt);
    SignZeroAuditService.logOne(e);

    publish(envelope.Id, SignZeroConstants.ACTION_SIGNED, recipient.Id);

    Integer stillToSign = [
      SELECT COUNT()
      FROM SignZero_Recipient__c
      WHERE
        SignZero_Request__c = :envelope.Id
        AND Status__c IN :SignZeroConstants.SIGNER_AWAITING
      WITH SYSTEM_MODE
    ];
    return new Map<String, Object>{ 'isFinalSigner' => stillToSign == 0 };
  }

  /**
   * @description Declines to sign, which closes the envelope for everyone.
   * @param rawToken the token from the signing link
   * @param reason why, shown to the sender (optional)
   * @param userAgent the signer's browser, for the audit trail
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   */
  @AuraEnabled
  public static void declineToSign(
    String rawToken,
    String reason,
    String userAgent,
    String passcodeSession
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken, passcodeSession);
    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = SignZeroConstants.SIGNER_DECLINED;
    recipient.Decline_Reason__c = reason == null ? null : reason.left(2000);
    recipient.Last_Known_IP__c = ip;
    recipient.Token_Expires_At__c = Datetime.now();
    recipient.Token_Encrypted__c = null;
    update as system recipient;
    update as system new SignZero_Request__c(
      Id = recipient.SignZero_Request__c,
      Status__c = SignZeroConstants.ENVELOPE_DECLINED
    );

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      SignZeroConstants.EVENT_DECLINED
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = reason;
    SignZeroAuditService.logOne(e);

    publish(recipient.SignZero_Request__c, SignZeroConstants.ACTION_DECLINED, recipient.Id);
  }

  /**
   * @description Delegates this signature to someone else. The original signer is kept as Reassigned; the new signer
   *   takes the same role and routing order and is invited by the progression job, so a failed email can be re-sent.
   * @param rawToken the token from the signing link
   * @param name the new signer's name
   * @param email the new signer's email address
   * @param reason why, shown to the sender (optional)
   * @param userAgent the signer's browser, for the audit trail
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   */
  @AuraEnabled
  public static void reassign(
    String rawToken,
    String name,
    String email,
    String reason,
    String userAgent,
    String passcodeSession
  ) {
    SignZero_Recipient__c recipient = openRecipient(rawToken, passcodeSession);
    if (!SignZeroSettings.allowReassignment()) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    name = name == null ? '' : name.trim();
    email = email == null ? '' : email.trim();
    if (String.isBlank(name) || !SignZeroConstants.EMAIL_PATTERN.matcher(email).matches()) {
      throw fail(System.Label.SZ_Reassign_Invalid);
    }
    if (email.equalsIgnoreCase(recipient.Email__c)) {
      throw fail(System.Label.SZ_Reassign_Same);
    }

    SignZero_Recipient__c delegate = new SignZero_Recipient__c(
      SignZero_Request__c = recipient.SignZero_Request__c,
      Name = name.left(80),
      Email__c = email,
      Signer_Role__c = recipient.Signer_Role__c,
      Routing_Order__c = recipient.Routing_Order__c,
      // Listed straight after the delegator: 2 -> 2.01, then 2.02.
      List_Order__c = (recipient.List_Order__c == null
        ? recipient.Routing_Order__c
        : recipient.List_Order__c) + 0.01,
      Delegated_From__c = recipient.Id,
      Status__c = SignZeroConstants.SIGNER_PENDING,
      // The delegate is checked the same way as the signer they replace.
      Auth_Method__c = recipient.Auth_Method__c
    );
    insert as system delegate;

    String ip = SignZeroAuditService.clientIp();
    recipient.Status__c = SignZeroConstants.SIGNER_REASSIGNED;
    recipient.Reassigned_To__c = delegate.Id;
    recipient.Reassign_Reason__c = reason == null ? null : reason.left(2000);
    recipient.Last_Known_IP__c = ip;
    recipient.User_Agent__c = clip(userAgent);
    recipient.Token_Expires_At__c = Datetime.now();
    recipient.Token_Encrypted__c = null;
    update as system recipient;

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      SignZeroConstants.EVENT_REASSIGNED
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = ('Reassigned to ' +
      delegate.Name +
      ' <' +
      email +
      '>' +
      (String.isBlank(reason) ? '' : ': ' + reason))
      .left(255);
    SignZeroAuditService.logOne(e);

    publish(recipient.SignZero_Request__c, SignZeroConstants.ACTION_REASSIGNED, delegate.Id);
  }

  /**
   * @description Emails the signer a one-time passcode for their link. Signers ask for it on the signing page, so
   *   email scanners that open links do not trigger codes. A new code replaces the previous one.
   * @param rawToken the token from the signing link
   * @param userAgent the signer's browser, for the audit trail
   * @return maskedEmail: where the code went; resendSeconds: how long until another code can be asked for
   */
  @AuraEnabled
  public static Map<String, Object> sendPasscode(String rawToken, String userAgent) {
    SignZero_Recipient__c recipient = findOpenableRecipient(rawToken);
    if (!requiresPasscode(recipient)) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    Datetime now = Datetime.now();
    if (
      recipient.Passcode_Sent_At__c != null &&
      recipient.Passcode_Sent_At__c.addSeconds(SignZeroConstants.PASSCODE_RESEND_SECONDS) > now
    ) {
      throw fail(System.Label.SZ_Err_Passcode_Wait);
    }
    Integer sends = recipient.Passcode_Sends__c == null ? 0 : recipient.Passcode_Sends__c.intValue();
    if (sends >= SignZeroConstants.PASSCODE_MAX_SENDS) {
      throw fail(System.Label.SZ_Err_Passcode_Limit);
    }

    // Uniform enough over 10^6 values: a 64-bit random number's modulo bias is negligible.
    Long range = Math.pow(10, SignZeroConstants.PASSCODE_DIGITS).longValue();
    String code = String.valueOf(Math.abs(Math.mod(Crypto.getRandomLong(), range)))
      .leftPad(SignZeroConstants.PASSCODE_DIGITS, '0');
    String ip = SignZeroAuditService.clientIp();
    recipient.Passcode_Hash__c = passcodeHash(recipient, code);
    recipient.Passcode_Expires_At__c = now.addMinutes(SignZeroConstants.PASSCODE_VALID_MINUTES);
    recipient.Passcode_Attempts__c = 0;
    recipient.Passcode_Sends__c = sends + 1;
    recipient.Passcode_Sent_At__c = now;
    recipient.Last_Known_IP__c = ip;
    update as system recipient;

    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      SignZeroConstants.EVENT_PASSCODE_SENT
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    e.details = ('One-time passcode emailed to ' + recipient.Email__c).left(255);
    SignZeroAuditService.logOne(e);

    SignZeroNotifier.Invitation inv = new SignZeroNotifier.Invitation();
    inv.email = recipient.Email__c;
    inv.recipientName = recipient.Name;
    inv.documentName = recipient.SignZero_Request__r.Document_Name__c;
    SignZeroNotifier.sendPasscode(inv, code);

    return new Map<String, Object>{
      'maskedEmail' => maskEmail(recipient.Email__c),
      'resendSeconds' => SignZeroConstants.PASSCODE_RESEND_SECONDS
    };
  }

  /**
   * @description Checks a one-time passcode. A wrong code is counted and the answer says so instead of throwing, so the
   *   count is saved; after too many wrong entries the code stops working.
   * @param rawToken the token from the signing link
   * @param code what the signer entered
   * @param userAgent the signer's browser, for the audit trail
   * @return verified; with a correct code, passcodeSession: the key the signing page sends with every later call;
   *   with a wrong one, triesLeft (0 when a new code is needed)
   */
  @AuraEnabled
  public static Map<String, Object> verifyPasscode(
    String rawToken,
    String code,
    String userAgent
  ) {
    SignZero_Recipient__c recipient = findOpenableRecipient(rawToken);
    if (!requiresPasscode(recipient)) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    Integer attempts = recipient.Passcode_Attempts__c == null ? 0 : recipient.Passcode_Attempts__c.intValue();
    if (
      recipient.Passcode_Hash__c == null ||
      recipient.Passcode_Expires_At__c == null ||
      recipient.Passcode_Expires_At__c < Datetime.now() ||
      attempts >= SignZeroConstants.PASSCODE_MAX_ATTEMPTS
    ) {
      throw fail(System.Label.SZ_Err_Passcode_Expired);
    }

    String ip = SignZeroAuditService.clientIp();
    code = code == null ? '' : code.deleteWhitespace();
    SignZeroAuditService.Entry e = new SignZeroAuditService.Entry(
      recipient.Id,
      recipient.SignZero_Request__c,
      SignZeroConstants.EVENT_PASSCODE_VERIFIED
    );
    e.ipAddress = ip;
    e.userAgent = userAgent;
    Map<String, Object> result = new Map<String, Object>();
    recipient.Last_Known_IP__c = ip;
    if (
      Pattern.matches('[0-9]{' + SignZeroConstants.PASSCODE_DIGITS + '}', code) &&
      passcodeHash(recipient, code) == recipient.Passcode_Hash__c
    ) {
      String passcodeSession = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
      // A code works once.
      recipient.Passcode_Hash__c = null;
      recipient.Passcode_Expires_At__c = null;
      recipient.Passcode_Session_Hash__c = SignZeroInvitationService.hashToken(passcodeSession);
      recipient.Passcode_Verified_At__c = Datetime.now();
      e.details = 'Signer entered the one-time passcode emailed to ' + recipient.Email__c;
      result.put('verified', true);
      result.put('passcodeSession', passcodeSession);
    } else {
      attempts++;
      recipient.Passcode_Attempts__c = attempts;
      Integer triesLeft = SignZeroConstants.PASSCODE_MAX_ATTEMPTS - attempts;
      if (triesLeft <= 0) {
        recipient.Passcode_Hash__c = null;
      }
      e.eventType = SignZeroConstants.EVENT_PASSCODE_FAILED;
      e.details = 'Wrong one-time passcode entered (' + attempts + ' of ' +
        SignZeroConstants.PASSCODE_MAX_ATTEMPTS + ')';
      result.put('verified', false);
      result.put('triesLeft', triesLeft);
    }
    update as system recipient;
    SignZeroAuditService.logOne(e);
    return result;
  }

  /**
   * @description Builds the answer to a signing page that must first ask for a passcode: nothing about the document.
   * @param recipient the signer
   * @return passcodeRequired, where the code goes, whether a code is already waiting, and branding
   */
  private static Map<String, Object> passcodeChallenge(SignZero_Recipient__c recipient) {
    Datetime now = Datetime.now();
    Integer resendIn = 0;
    if (recipient.Passcode_Sent_At__c != null) {
      Long waitMs =
        recipient.Passcode_Sent_At__c.addSeconds(SignZeroConstants.PASSCODE_RESEND_SECONDS).getTime() -
        now.getTime();
      resendIn = Math.max(0, Math.ceil(waitMs / 1000.0).intValue());
    }
    return new Map<String, Object>{
      'passcodeRequired' => true,
      'recipientName' => recipient.Name,
      'maskedEmail' => maskEmail(recipient.Email__c),
      // A code already sent and still usable, e.g. after a reload: the page goes straight to entering it.
      'passcodeSent' => recipient.Passcode_Hash__c != null &&
        recipient.Passcode_Expires_At__c != null &&
        recipient.Passcode_Expires_At__c > now,
      'resendSeconds' => resendIn,
      'passcodeDigits' => SignZeroConstants.PASSCODE_DIGITS,
      'passcodeValidMinutes' => SignZeroConstants.PASSCODE_VALID_MINUTES,
      'performanceLogs' => SignZeroSettings.performanceLogs(),
      'pdfHostVersion' => SignZeroSettings.pdfHostVersion(),
      'branding' => SignZeroSettings.branding()
    };
  }

  /**
   * @description Whether the signer must enter a one-time passcode, as decided when the envelope was sent.
   * @param r the recipient (Auth_Method__c)
   * @return true for a link and passcode signer
   */
  private static Boolean requiresPasscode(SignZero_Recipient__c r) {
    return r.Auth_Method__c == SignZeroConstants.AUTH_LINK_AND_PASSCODE;
  }

  /**
   * @description Whether the signing page may act for the signer: no passcode is needed, or it sent the key from a
   *   correct passcode within the last PASSCODE_SESSION_HOURS.
   * @param r the recipient
   * @param passcodeSession the key from verifyPasscode
   * @return true when the signer is verified
   */
  private static Boolean passcodeVerified(SignZero_Recipient__c r, String passcodeSession) {
    if (!requiresPasscode(r)) {
      return true;
    }
    return String.isNotBlank(passcodeSession) &&
      Pattern.matches('[0-9a-f]{64}', passcodeSession) &&
      r.Passcode_Session_Hash__c == SignZeroInvitationService.hashToken(passcodeSession) &&
      r.Passcode_Verified_At__c != null &&
      r.Passcode_Verified_At__c.addHours(SignZeroConstants.PASSCODE_SESSION_HOURS) > Datetime.now();
  }

  /**
   * @description Hashes a passcode with the org key, tied to the signer and their current link, so a stored hash
   *   neither reveals the code nor works for anyone else.
   * @param r the recipient (Id, Token_Hash__c)
   * @param code the six digits
   * @return the keyed hash
   */
  private static String passcodeHash(SignZero_Recipient__c r, String code) {
    return SignZeroTokenVault.mac(r.Id + ':' + r.Token_Hash__c + ':' + code);
  }

  /**
   * @description Shows enough of an email address for the signer to recognise it: c***@example.com.
   * @param email the address
   * @return the masked address
   */
  @TestVisible
  private static String maskEmail(String email) {
    if (String.isBlank(email) || !email.contains('@')) {
      return '';
    }
    return email.left(1) + '***' + email.substring(email.lastIndexOf('@'));
  }

  /**
   * @description Checks the places a signer chose for their signature and describes them for the audit trail.
   * @param signerPlacements JSON [{page, x, y}] from the signing page; blank when the signer did not choose
   * @return e.g. "page 2 at (76, 607)", or null when the signer did not choose
   */
  private static String describePlacements(String signerPlacements) {
    if (String.isBlank(signerPlacements)) {
      return null;
    }
    List<SignZeroFieldLayout.Placement> placements;
    try {
      placements = (List<SignZeroFieldLayout.Placement>) JSON.deserialize(
        signerPlacements,
        List<SignZeroFieldLayout.Placement>.class
      );
    } catch (JSONException e) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    if (
      !SignZeroSettings.allowSignerPlacement() ||
      placements == null ||
      placements.isEmpty() ||
      placements.size() > SignZeroConstants.MAX_FIELD_PLACEMENTS
    ) {
      throw fail(System.Label.SZ_Generic_Error);
    }
    List<String> described = new List<String>();
    for (SignZeroFieldLayout.Placement p : placements) {
      if (p == null || p.page == null || p.page < 0 || p.x == null || p.y == null) {
        throw fail(System.Label.SZ_Generic_Error);
      }
      described.add(
        'page ' + (p.page + 1) + ' at (' + p.x.round() + ', ' + p.y.round() + ')'
      );
    }
    return String.join(described, ', ').left(1000);
  }

  /**
   * @description Finds the recipient whose link may sign or decline right now.
   * @param rawToken the token from the signing link
   * @param passcodeSession the key from verifyPasscode, when the signer must enter a one-time passcode
   * @return the recipient, with their envelope; throws when the link cannot sign or the signer is not verified
   */
  private static SignZero_Recipient__c openRecipient(String rawToken, String passcodeSession) {
    SignZero_Recipient__c r = findRecipient(rawToken);
    if (!isSignable(r)) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    if (!passcodeVerified(r, passcodeSession)) {
      throw fail(System.Label.SZ_Err_Passcode_Required);
    }
    return r;
  }

  /**
   * @description Finds the recipient whose link may open the signing page: to sign, or read-only after signing.
   * @param rawToken the token from the signing link
   * @return the recipient, with their envelope; throws when the link cannot open the page
   */
  private static SignZero_Recipient__c findOpenableRecipient(String rawToken) {
    SignZero_Recipient__c r = findRecipient(rawToken);
    // Recalled envelopes were already refused by findRecipient.
    if (!isSignable(r) && r.Status__c != SignZeroConstants.SIGNER_SIGNED) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    return r;
  }

  /**
   * @description Whether it is this signer's turn on an envelope still out for signature.
   * @param r the recipient, with their envelope status
   * @return true when the signer may sign or decline
   */
  private static Boolean isSignable(SignZero_Recipient__c r) {
    return SignZeroConstants.SIGNER_OPEN.contains(r.Status__c) &&
      r.SignZero_Request__r.Status__c == SignZeroConstants.ENVELOPE_OUT_FOR_SIGNATURE;
  }

  /**
   * @description Finds the recipient a live, unexpired token belongs to.
   * @param rawToken the token from the signing link
   * @return the recipient, with their envelope; throws a readable reason when the link does not work
   */
  private static SignZero_Recipient__c findRecipient(String rawToken) {
    SignZeroRecordGuard.markProcessUpdate();
    if (
      String.isBlank(rawToken) || !Pattern.matches('[0-9a-f]{64}', rawToken)
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    List<SignZero_Recipient__c> rows = [
      SELECT
        Id,
        Name,
        Email__c,
        Signer_Role__c,
        Routing_Order__c,
        List_Order__c,
        Status__c,
        Token_Expires_At__c,
        Viewed_At__c,
        Consented_At__c,
        Signed_At__c,
        Token_Hash__c,
        Auth_Method__c,
        Passcode_Hash__c,
        Passcode_Expires_At__c,
        Passcode_Attempts__c,
        Passcode_Sends__c,
        Passcode_Sent_At__c,
        Passcode_Session_Hash__c,
        Passcode_Verified_At__c,
        SignZero_Request__c,
        SignZero_Request__r.Name,
        SignZero_Request__r.Status__c,
        SignZero_Request__r.Document_Name__c,
        SignZero_Request__r.Working_Copy_Id__c,
        SignZero_Request__r.Working_Copy_Hash__c,
        SignZero_Request__r.Field_Layout__c
      FROM SignZero_Recipient__c
      WHERE Token_Hash__c = :SignZeroInvitationService.hashToken(rawToken)
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    SignZero_Recipient__c r = rows[0];
      // Before expiry: recalling expires every link, and the signer should be told why.
    if (r.SignZero_Request__r.Status__c == SignZeroConstants.ENVELOPE_VOIDED) {
      throw fail(System.Label.SZ_Err_Recalled);
    }
    if (
      r.Token_Expires_At__c == null ||
      r.Token_Expires_At__c < Datetime.now()
    ) {
      throw fail(System.Label.SZ_Err_Invalid_Session);
    }
    return r;
  }

  /**
   * @description Publishes a SignZero_Event__e so the progression job moves the envelope on. EventBus.publish reports
   *   failures instead of throwing, so the result is checked: a lost event would leave the envelope stuck.
   * @param requestId the envelope
   * @param action what the signer did (an ACTION_* constant)
   * @param recipientId the signer
   */
  private static void publish(Id requestId, String action, Id recipientId) {
    Database.SaveResult result = EventBus.publish(
      new SignZero_Event__e(
        SignZero_Request_Id__c = requestId,
        Action__c = action,
        Recipient_Id__c = recipientId
      )
    );
    if (!result.isSuccess()) {
      throw new SignZeroSettings.SignZeroException(
        'Could not queue envelope progress: ' +
        result.getErrors()[0].getMessage()
      );
    }
  }

  /**
   * @description Shortens text to fit a 255-character field.
   * @param s any text
   * @return the first 255 characters, or null
   */
  private static String clip(String s) {
    return s == null ? null : s.left(255);
  }

  /**
   * @description Builds an error the signing page shows as is.
   * @param message the message for the signer
   * @return the exception to throw
   */
  private static AuraHandledException fail(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
