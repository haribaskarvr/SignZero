@IsTest
private class SignZeroTest {
  private static final String TOKEN_A = 'a'.repeat(64);
  private static final String TOKEN_B = 'b'.repeat(64);
  private static final String SIGNED_PDF = EncodingUtil.base64Encode(
    Blob.valueOf('%PDF-1.4 signed content')
  );

  @TestSetup
  static void setup() {
    Account acct = new Account(Name = 'Acme');
    insert acct;
    insert new Account(Name = 'Acme Holdings');
    insert new ContentVersion(
      Title = 'MSA',
      PathOnClient = 'MSA.pdf',
      VersionData = Blob.valueOf('%PDF-1.4 original {{sig:Customer}}'),
      FirstPublishLocationId = acct.Id
    );
  }

  private static void useTestSettings() {
    SignZeroSettings.cached = new SignZero_Setting__mdt(
      DeveloperName = 'Default',
      Site_Base_Url__c = 'https://acme.my.site.com/esign/',
      Allow_Reassignment__c = true,
      Token_Validity_Days__c = 3,
      Max_Document_Size_KB__c = 100,
      Company_Name__c = 'Acme Corp',
      Primary_Color__c = '#123456',
      Accent_Color__c = 'red;background:url(x)'
    );
  }

  private static Id dispatchTwoSigners() {
    useTestSettings();
    Account acct = [SELECT Id FROM Account WHERE Name = 'Acme'];
    Account holding = [SELECT Id FROM Account WHERE Name = 'Acme Holdings'];
    ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1];
    SignZeroOrchestrator.DispatchRequest req = new SignZeroOrchestrator.DispatchRequest();
    req.sourceRecordId = acct.Id;
    req.contentDocumentId = cv.ContentDocumentId;
    req.documentName = 'Master Services Agreement';
    req.recipientName = 'Casey Customer';
    req.recipientEmail = 'casey@example.com';
    req.additionalRecordIds = new List<Id>{ holding.Id };
    req.additionalSigners = new List<SignZeroSigner>{
      // Lower case on purpose: roles are matched to the picklist ignoring case.
      new SignZeroSigner('Vic Vendor', 'vic@example.com', 'vendor', null)
    };
    return SignZeroOrchestrator.execute(
        new List<SignZeroOrchestrator.DispatchRequest>{ req }
      )[0]
      .signatureRequestId;
  }

  private static SignZero_Recipient__c recipient(Id requestId, Integer order) {
    return [
      SELECT
        Id,
        Status__c,
        Token_Hash__c,
        Signer_Role__c,
        Sent_At__c,
        Consented_At__c,
        Signed_At__c,
        Signature_Method__c
      FROM SignZero_Recipient__c
      WHERE SignZero_Request__c = :requestId AND Routing_Order__c = :order
    ];
  }

  // Tokens only exist in the invitation email, so tests plant a known one.
  private static void plantToken(Id recipientId, String rawToken) {
    SignZeroRecordGuard.processUpdate = true;
    update as system new SignZero_Recipient__c(
      Id = recipientId,
      Token_Hash__c = SignZeroInvitationService.hashToken(rawToken),
      Token_Expires_At__c = Datetime.now().addDays(1)
    );
  }

  private static Map<String, Object> signAs(String rawToken) {
    return signAs(rawToken, SIGNED_PDF);
  }

  private static Map<String, Object> signAs(String rawToken, String pdfBase64) {
    SignZeroGatewayController.initializeSession(
      rawToken,
      'TestAgent/1.0'
    );
    SignZeroGatewayController.recordConsent(rawToken, 'TestAgent/1.0');
    return SignZeroGatewayController.submitExecutedDocument(
      rawToken,
      pdfBase64,
      EncodingUtil.base64Encode(Blob.valueOf('png')),
      'Typed',
      'TestAgent/1.0'
    );
  }

  @IsTest
  static void dispatchInvitesOnlyFirstRoutingOrder() {
    Test.startTest();
    Id requestId = dispatchTwoSigners();
    Integer emails = SignZeroNotifier.sentInTest.size();
    Test.stopTest();

    SignZero_Request__c env = [
      SELECT
        Status__c,
        Pre_Sign_Hash__c,
        Working_Copy_Id__c,
        Working_Copy_Hash__c
      FROM SignZero_Request__c
      WHERE Id = :requestId
    ];
    Assert.areEqual('Out for Signature', env.Status__c);
    Assert.areEqual(
      SignZeroSealService.computeSHA256Hash(
        Blob.valueOf('%PDF-1.4 original {{sig:Customer}}')
      ),
      env.Pre_Sign_Hash__c
    );
    Assert.isNotNull(env.Working_Copy_Id__c);
    Assert.areEqual(env.Pre_Sign_Hash__c, env.Working_Copy_Hash__c);

    SignZero_Recipient__c first = recipient(requestId, 1);
    SignZero_Recipient__c second = recipient(requestId, 2);
    Assert.areEqual('Sent', first.Status__c);
    Assert.areEqual(64, first.Token_Hash__c.length());
    Assert.areEqual('Customer', first.Signer_Role__c);
    Assert.areEqual('Pending', second.Status__c);
    Assert.isNull(second.Token_Hash__c);
    Assert.areEqual('Vendor', second.Signer_Role__c);
    Assert.areEqual(1, emails);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Event_Type__c = 'Sent'
      ]
    );
  }

  @IsTest
  static void fullSequentialSigningSealsEnvelope() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c first = recipient(requestId, 1);
    plantToken(first.Id, TOKEN_A);

    Test.startTest();
    Assert.areEqual(false, signAs(TOKEN_A).get('isFinalSigner'));
    Test.getEventBus().deliver();
    Test.stopTest(); // runs the progression job enqueued by the event trigger

    first = recipient(requestId, 1);
    Assert.areEqual('Signed', first.Status__c);
    Assert.isNotNull(first.Consented_At__c);
    Assert.areEqual('Typed in a selected style', first.Signature_Method__c);
    SignZero_Recipient__c second = recipient(requestId, 2);
    Assert.areEqual(
      'Sent',
      second.Status__c,
      'next routing order is invited after the first signs'
    );

    plantToken(second.Id, TOKEN_B);
    Map<String, Object> last = signAs(
      TOKEN_B,
      EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 fully signed'))
    );
    Assert.areEqual(
      true,
      last.get('isFinalSigner'),
      'the last signer completes the envelope'
    );
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);

    SignZero_Request__c env = [
      SELECT
        Status__c,
        Post_Sign_Hash__c,
        Final_Document_Version_Id__c,
        Certificate_Version_Id__c,
        Completed_At__c
      FROM SignZero_Request__c
      WHERE Id = :requestId
    ];
    Assert.areEqual('Completed', env.Status__c);
    Assert.areEqual(
      SignZeroSealService.computeSHA256Hash(
        Blob.valueOf('%PDF-1.4 fully signed')
      ),
      env.Post_Sign_Hash__c
    );
    Assert.isNotNull(env.Certificate_Version_Id__c);
    Assert.isNotNull(env.Completed_At__c);

    Account acct = [SELECT Id FROM Account WHERE Name = 'Acme'];
    Account holding = [SELECT Id FROM Account WHERE Name = 'Acme Holdings'];
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :holding.Id
      ],
      'executed agreement and certificate are also filed on the extra record'
    );
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :acct.Id],
      'original + executed + certificate are filed on the source record'
    );
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Event_Type__c = 'Completed'
      ]
    );
    Assert.isTrue(SignZeroAuditService.verifyChain(requestId));

    // Reopening the link after signing shows the completed document read-only...
    Map<String, Object> view = SignZeroGatewayController.initializeSession(
      TOKEN_B,
      'x'
    );
    Assert.areEqual(true, view.get('readOnly'));
    Assert.areEqual('Completed', view.get('envelopeStatus'));
    Assert.isNotNull(view.get('pdfBase64'));
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Details__c = 'Read-only view after signing'
      ]
    );
    // ...but the link can never sign or decline again.
    try {
      SignZeroGatewayController.submitExecutedDocument(
        TOKEN_B,
        SIGNED_PDF,
        null,
        'Typed',
        'x'
      );
      Assert.fail('expected the used token to be rejected for signing');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('invalid'));
    }
  }

  @IsTest
  static void guestUserCanCompleteSigning() {
    List<User> guests = [
      SELECT Id
      FROM User
      WHERE UserType = 'Guest' AND IsActive = TRUE
      LIMIT 1
    ];
    if (guests.isEmpty()) {
      return; // org without an Experience site
    }
    Id requestId = dispatchTwoSigners();
    plantToken(recipient(requestId, 1).Id, TOKEN_A);

    Test.startTest();
    System.runAs(guests[0]) {
      Map<String, Object> session = SignZeroGatewayController.initializeSession(
        TOKEN_A,
        'GuestAgent'
      );
      Assert.isNotNull(
        session.get('pdfBase64'),
        'guest must be able to read the working copy'
      );
      signAs(TOKEN_A);
    }
    Test.stopTest();

    SignZero_Request__c env = [
      SELECT Working_Copy_Hash__c
      FROM SignZero_Request__c
      WHERE Id = :requestId
    ];
    Assert.areEqual(
      SignZeroSealService.computeSHA256Hash(
        Blob.valueOf('%PDF-1.4 signed content')
      ),
      env.Working_Copy_Hash__c
    );
    Assert.areEqual('Signed', recipient(requestId, 1).Status__c);
  }

  @IsTest
  static void initializeSessionReturnsDocumentAndBranding() {
    Id requestId = dispatchTwoSigners();
    plantToken(recipient(requestId, 1).Id, TOKEN_A);

    Map<String, Object> session = SignZeroGatewayController.initializeSession(
      TOKEN_A,
      'TestAgent'
    );

    Assert.areEqual('Casey Customer', session.get('recipientName'));
    Assert.areEqual('Master Services Agreement', session.get('documentName'));
    Assert.areEqual(false, session.get('consentAccepted'));
    Assert.areEqual(
      EncodingUtil.base64Encode(
        Blob.valueOf('%PDF-1.4 original {{sig:Customer}}')
      ),
      session.get('pdfBase64')
    );
    Map<String, String> branding = (Map<String, String>) session.get(
      'branding'
    );
    Assert.areEqual('Acme Corp', branding.get('companyName'));
    Assert.areEqual('#123456', branding.get('primaryColor'));
    Assert.isNull(
      branding.get('accentColor'),
      'unsafe colour values are dropped so the site theme applies'
    );
    Assert.areEqual('Viewed', recipient(requestId, 1).Status__c);
  }

  @IsTest
  static void gatewayRejectsBadRequests() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c first = recipient(requestId, 1);
    plantToken(first.Id, TOKEN_A);

    assertGatewayError('not-a-token', null, 'invalid');
    assertGatewayError('c'.repeat(64), null, 'invalid');
    assertGatewayError(TOKEN_A, SIGNED_PDF, 'disclosure');

    SignZeroGatewayController.recordConsent(TOKEN_A, 'x');
    try {
      SignZeroGatewayController.submitExecutedDocument(
        TOKEN_A,
        SIGNED_PDF,
        null,
        'Stamp',
        'x'
      );
      Assert.fail('an unknown signature method must be rejected');
    } catch (AuraHandledException e) {
      Assert.areEqual(System.Label.SZ_Generic_Error, e.getMessage());
    }
    assertGatewayError(
      TOKEN_A,
      EncodingUtil.base64Encode(Blob.valueOf('<html>')),
      'valid PDF'
    );
    assertGatewayError(
      TOKEN_A,
      EncodingUtil.base64Encode(
        Blob.valueOf('%PDF-1.4 original {{sig:Customer}}')
      ),
      'No signature'
    );

    SignZeroRecordGuard.processUpdate = true;
    update as system new SignZero_Recipient__c(
      Id = first.Id,
      Token_Expires_At__c = Datetime.now().addMinutes(-1)
    );
    assertGatewayError(TOKEN_A, SIGNED_PDF, 'expired');
  }

  private static void assertGatewayError(
    String token,
    String pdf,
    String expected
  ) {
    try {
      if (pdf == null) {
        SignZeroGatewayController.initializeSession(token, 'x');
      } else {
        SignZeroGatewayController.submitExecutedDocument(
          token,
          pdf,
          null,
          'Drawn',
          'x'
        );
      }
      Assert.fail('expected an error containing ' + expected);
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains(expected), e.getMessage());
    }
  }

  @IsTest
  static void declineStopsEnvelopeAndNotifiesOwner() {
    Id requestId = dispatchTwoSigners();
    plantToken(recipient(requestId, 1).Id, TOKEN_A);

    Test.startTest();
    SignZeroGatewayController.declineToSign(
      TOKEN_A,
      'Wrong pricing',
      'x'
    );
    new SignZeroProgressionJob(new Set<Id>(), new Set<Id>{ requestId })
      .execute(null);
    Test.stopTest();

    Assert.areEqual(
      'Declined',
      [SELECT Status__c FROM SignZero_Request__c WHERE Id = :requestId]
      .Status__c
    );
    Assert.areEqual('Declined', recipient(requestId, 1).Status__c);
    Assert.areEqual('Pending', recipient(requestId, 2).Status__c);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Event_Type__c = 'Declined' AND Details__c = 'Wrong pricing'
      ]
    );
  }

  @IsTest
  static void auditLedgerIsImmutableAndCompletedEnvelopesCannotBeDeleted() {
    Id requestId = dispatchTwoSigners();
    SignZero_Audit_Trail__c evt = [
      SELECT Id
      FROM SignZero_Audit_Trail__c
      LIMIT 1
    ];

    Database.SaveResult upd = Database.update(
      new SignZero_Audit_Trail__c(Id = evt.Id, Details__c = 'tampered'),
      false,
      AccessLevel.SYSTEM_MODE
    );
    Assert.isFalse(upd.isSuccess());
    Assert.isFalse(
      Database.delete(evt.Id, false, AccessLevel.SYSTEM_MODE).isSuccess()
    );

    SignZeroRecordGuard.processUpdate = true;
    update as system new SignZero_Request__c(
      Id = requestId,
      Status__c = 'Completed'
    );
    SignZeroRecordGuard.processUpdate = false;
    Assert.isFalse(
      Database.delete(requestId, false, AccessLevel.SYSTEM_MODE).isSuccess()
    );
  }

  @IsTest
  static void flowDispatchWithSignerListOnly() {
    // The "SignZero: Send for Signature" flow passes only the signer editor's list, with explicit orders.
    useTestSettings();
    Account acct = [SELECT Id FROM Account WHERE Name = 'Acme'];
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'MSA'].ContentDocumentId;
    SignZeroOrchestrator.DispatchRequest req = new SignZeroOrchestrator.DispatchRequest();
    req.sourceRecordId = acct.Id;
    req.contentDocumentId = docId;
    req.documentName = 'MSA via flow';
    req.additionalSigners = new List<SignZeroSigner>{
      new SignZeroSigner('Casey Customer', 'casey@example.com', 'Customer', 1),
      new SignZeroSigner('Cleo Cosigner', 'cleo@example.com', 'Customer', 1),
      new SignZeroSigner('Vic Vendor', 'vic@example.com', 'Vendor', 2)
    };

    Id requestId = SignZeroOrchestrator.execute(
        new List<SignZeroOrchestrator.DispatchRequest>{ req }
      )[0]
      .signatureRequestId;

    Map<String, SignZero_Recipient__c> byEmail = new Map<String, SignZero_Recipient__c>();
    for (SignZero_Recipient__c r : [
      SELECT Email__c, Routing_Order__c, List_Order__c, Status__c
      FROM SignZero_Recipient__c
      WHERE SignZero_Request__c = :requestId
    ]) {
      byEmail.put(r.Email__c, r);
    }
    Assert.areEqual(3, byEmail.size());
    Assert.areEqual('Sent', byEmail.get('casey@example.com').Status__c, 'order 1 signers are invited together');
    Assert.areEqual('Sent', byEmail.get('cleo@example.com').Status__c);
    Assert.areEqual('Pending', byEmail.get('vic@example.com').Status__c, 'order 2 waits');
    Assert.areEqual(2, byEmail.get('vic@example.com').List_Order__c);
  }

  @IsTest
  static void dispatchValidatesInput() {
    useTestSettings();
    Account acct = [SELECT Id FROM Account LIMIT 1];
    ContentVersion txt = new ContentVersion(
      Title = 'notes',
      PathOnClient = 'notes.txt',
      VersionData = Blob.valueOf('hi')
    );
    insert txt;
    Id txtDoc = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :txt.Id
    ]
    .ContentDocumentId;
    Id pdfDoc = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Title = 'MSA'
    ]
    .ContentDocumentId;

    assertDispatchError(
      acct.Id,
      txtDoc,
      'Pat',
      'pat@example.com',
      'only supports PDF'
    );
    assertDispatchError(acct.Id, pdfDoc, null, null, 'At least one signer');
    assertDispatchError(
      acct.Id,
      pdfDoc,
      'Pat',
      'not-an-email',
      'Invalid signer email'
    );
    assertDispatchError(acct.Id, pdfDoc, '', 'pat@example.com', 'needs a name');
    assertDispatchError(
      acct.Id,
      pdfDoc,
      'Pat',
      'pat@example.com',
      'Landlord',
      'Unknown signer role "Landlord"'
    );

    SignZeroSettings.cached.Max_Document_Size_KB__c = null;
    SignZeroSettings.cached.Token_Validity_Days__c = null;
    Assert.areEqual(2000 * 1024, SignZeroSettings.maxDocumentBytes());
    Assert.areEqual(7, SignZeroSettings.tokenValidityDays());
    Assert.isFalse(SignZeroSettings.performanceLogs());
    insert new SignZero_Diagnostics__c(
      SetupOwnerId = UserInfo.getUserId(),
      Performance_Logs__c = true
    );
    Assert.isTrue(SignZeroSettings.performanceLogs());
    Assert.isNotNull(SignZeroSettings.pdfHostVersion());
    Assert.areEqual(
      'https://acme.my.site.com/esign',
      SignZeroSettings.signingBaseUrl()
    );
  }

  private static void assertDispatchError(
    Id source,
    Id doc,
    String name,
    String email,
    String expected
  ) {
    assertDispatchError(source, doc, name, email, null, expected);
  }

  private static void assertDispatchError(
    Id source,
    Id doc,
    String name,
    String email,
    String role,
    String expected
  ) {
    SignZeroOrchestrator.DispatchRequest req = new SignZeroOrchestrator.DispatchRequest();
    req.sourceRecordId = source;
    req.contentDocumentId = doc;
    req.documentName = 'Doc';
    req.recipientName = name;
    req.recipientEmail = email;
    req.signerRole = role;
    try {
      SignZeroOrchestrator.execute(
        new List<SignZeroOrchestrator.DispatchRequest>{ req }
      );
      Assert.fail('expected ' + expected);
    } catch (SignZeroSettings.SignZeroException e) {
      Assert.isTrue(e.getMessage().contains(expected), e.getMessage());
    }
  }

  @IsTest
  static void failedInvitationIsRolledBackAndReported() {
    Id requestId = dispatchTwoSigners();
    plantToken(recipient(requestId, 1).Id, TOKEN_A);
    signAs(TOKEN_A);

    SignZeroNotifier.failSendsInTest = true;
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);

    SignZero_Recipient__c next = recipient(requestId, 2);
    Assert.areEqual(
      'Pending',
      next.Status__c,
      'a signer whose email failed must not be marked as invited'
    );
    Assert.isNull(next.Token_Hash__c);
    Assert.isTrue(
      [SELECT Error_Message__c FROM SignZero_Request__c WHERE Id = :requestId]
        .Error_Message__c.contains('Could not invite')
    );
  }

  @IsTest
  static void resendRecoversAFailedInvitation() {
    Id requestId = dispatchTwoSigners();
    plantToken(recipient(requestId, 1).Id, TOKEN_A);
    signAs(TOKEN_A);
    SignZeroNotifier.failSendsInTest = true;
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);
    SignZeroNotifier.failSendsInTest = false;

    List<SignZeroResendController.Target> preview = SignZeroResendController.previewResend(
      requestId
    );
    Assert.areEqual(1, preview.size());
    Assert.areEqual(
      'vic@example.com',
      preview[0].email,
      'only the signer whose turn it is is re-invited'
    );

    Assert.areEqual(1, SignZeroResendController.resend(requestId));
    SignZero_Recipient__c next = recipient(requestId, 2);
    Assert.areEqual('Sent', next.Status__c);
    Assert.isNotNull(next.Token_Hash__c);
    Assert.isNull(
      [SELECT Error_Message__c FROM SignZero_Request__c WHERE Id = :requestId]
      .Error_Message__c
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE
          SignZero_Recipient__c = :next.Id
          AND Details__c LIKE '%re-sent by%'
      ]
    );

    // A signer who has already signed cannot be re-sent.
    try {
      SignZeroResendController.previewResend(recipient(requestId, 1).Id);
      Assert.fail('expected an error for a signed signer');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('already signed'), e.getMessage());
    }
  }

  @IsTest
  static void resendReplacesTheOldLink() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c first = recipient(requestId, 1);
    plantToken(first.Id, TOKEN_A);
    SignZeroGatewayController.initializeSession(TOKEN_A, 'x');

    SignZeroResendController.resend(first.Id);

    Assert.areEqual(
      'Viewed',
      recipient(requestId, 1).Status__c,
      'a resend keeps the signer progress'
    );
    try {
      SignZeroGatewayController.initializeSession(TOKEN_A, 'x');
      Assert.fail('the old link must stop working');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('invalid'));
    }
  }

  @IsTest
  static void signerCanReassignToSomeoneElse() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c original = recipient(requestId, 1);
    plantToken(original.Id, TOKEN_A);

    assertReassignRejected(TOKEN_A, 'Dana', 'not-an-email');
    assertReassignRejected(TOKEN_A, 'Casey Again', 'casey@example.com');

    SignZeroGatewayController.reassign(
      TOKEN_A,
      'Dana Delegate',
      'dana@example.com',
      'On leave',
      'x'
    );
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);

    original = [
      SELECT Status__c, Reassigned_To__c, Reassign_Reason__c
      FROM SignZero_Recipient__c
      WHERE Id = :original.Id
    ];
    Assert.areEqual('Reassigned', original.Status__c);
    Assert.areEqual('On leave', original.Reassign_Reason__c);
    SignZero_Recipient__c delegate = [
      SELECT
        Id,
        Status__c,
        Signer_Role__c,
        Routing_Order__c,
        Token_Hash__c,
        List_Order__c,
        Delegated_From__c,
        Status_Display__c
      FROM SignZero_Recipient__c
      WHERE Id = :original.Reassigned_To__c
    ];
    Assert.areEqual(1.01, delegate.List_Order__c, 'listed straight after the signer who delegated');
    Assert.areEqual(original.Id, delegate.Delegated_From__c);
    Assert.isTrue(delegate.Status_Display__c.contains('delegate of Casey Customer'), delegate.Status_Display__c);
    Assert.areEqual(
      'Sent',
      delegate.Status__c,
      'the delegate is invited by the progression job'
    );
    Assert.areEqual('Customer', delegate.Signer_Role__c);
    Assert.areEqual(1, delegate.Routing_Order__c);
    Assert.areEqual(
      2,
      [SELECT Signers_Total__c FROM SignZero_Request__c WHERE Id = :requestId]
      .Signers_Total__c,
      'a reassigned signer no longer counts as a signer'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Event_Type__c = 'Reassigned'
      ]
    );
    try {
      SignZeroGatewayController.initializeSession(TOKEN_A, 'x');
      Assert.fail('the original link must stop working');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('invalid'));
    }

    // The delegate signs, and routing continues to the next signer.
    plantToken(delegate.Id, TOKEN_B);
    Assert.areEqual(false, signAs(TOKEN_B).get('isFinalSigner'));
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);
    Assert.areEqual('Sent', recipient(requestId, 2).Status__c);
  }

  private static void assertReassignRejected(
    String token,
    String name,
    String email
  ) {
    try {
      SignZeroGatewayController.reassign(token, name, email, null, 'x');
      Assert.fail('expected reassignment to be rejected');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().startsWith('Please enter'), e.getMessage());
    }
  }

  @IsTest
  static void manualEditsToEvidenceAreBlocked() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c sent = recipient(requestId, 1);
    SignZero_Recipient__c pending = recipient(requestId, 2);
    SignZeroRecordGuard.processUpdate = false; // from here on, edits come from a person

    // System mode so the trigger, not field permissions, is what is being tested.
    assertBlocked(
      new SignZero_Request__c(Id = requestId, Pre_Sign_Hash__c = 'forged'),
      'maintained by SignZero'
    );
    assertBlocked(
      new SignZero_Request__c(Id = requestId, Status__c = 'Completed'),
      'Recall Envelope action'
    );
    assertBlocked(
      new SignZero_Recipient__c(Id = sent.Id, Status__c = 'Signed'),
      'maintained by SignZero'
    );
    assertBlocked(
      new SignZero_Recipient__c(Id = sent.Id, Email__c = 'new@example.com'),
      'after their invitation'
    );
    Assert.isTrue(
      Database.update(
          new SignZero_Recipient__c(
            Id = pending.Id,
            Email__c = 'vic2@example.com'
          ),
          false,
          AccessLevel.SYSTEM_MODE
        )
        .isSuccess(),
      'a signer who has not been invited yet can still be corrected'
    );
    Assert.isFalse(
      Database.insert(
          new SignZero_Recipient__c(
            SignZero_Request__c = requestId,
            Name = 'X',
            Email__c = 'x@example.com'
          ),
          false,
          AccessLevel.SYSTEM_MODE
        )
        .isSuccess()
    );
    Assert.isFalse(
      Database.insert(
          new SignZero_Audit_Trail__c(
            SignZero_Recipient__c = sent.Id,
            Event_Type__c = 'Signed'
          ),
          false,
          AccessLevel.SYSTEM_MODE
        )
        .isSuccess()
    );
    Assert.isFalse(
      Database.delete(sent.Id, false, AccessLevel.SYSTEM_MODE).isSuccess()
    );
    Assert.isFalse(
      Database.delete(requestId, false, AccessLevel.SYSTEM_MODE).isSuccess(),
      'sent envelopes cannot be deleted'
    );

    // Voiding by hand would skip closing the links, the emails and the audit trail.
    assertBlocked(
      new SignZero_Request__c(Id = requestId, Status__c = 'Voided'),
      'Recall Envelope action'
    );
    assertBlocked(
      new SignZero_Request__c(Id = requestId, Recall_Reason__c = 'forged'),
      'maintained by SignZero'
    );
  }

  @IsTest
  static void recallVoidsEnvelopeClosesLinksAndNotifiesSigners() {
    Id requestId = dispatchTwoSigners();
    SignZero_Recipient__c first = recipient(requestId, 1);
    plantToken(first.Id, TOKEN_A);
    SignZeroGatewayController.initializeSession(TOKEN_A, 'x');

    List<SignZeroResendController.Target> preview = SignZeroRecallController.previewRecall(
      requestId
    );
    Assert.areEqual(1, preview.size(), 'only signers who were sent a link');
    Assert.areEqual('casey@example.com', preview[0].email);

    SignZeroNotifier.sentInTest.clear();
    Test.startTest();
    SignZeroRecallController.Result result = SignZeroRecallController.recall(
      requestId,
      '  Wrong version attached '
    );
    Test.stopTest();

    Assert.areEqual(1, result.notified);
    Assert.isNull(result.warning);
    SignZero_Request__c env = [
      SELECT Status__c, Recall_Reason__c, Error_Message__c
      FROM SignZero_Request__c
      WHERE Id = :requestId
    ];
    Assert.areEqual('Voided', env.Status__c);
    Assert.areEqual('Wrong version attached', env.Recall_Reason__c);
    Assert.areEqual('Voided', recipient(requestId, 1).Status__c);
    Assert.areEqual('Voided', recipient(requestId, 2).Status__c);

    Assert.areEqual(1, SignZeroNotifier.sentInTest.size());
    Messaging.SingleEmailMessage mail = SignZeroNotifier.sentInTest[0];
    Assert.areEqual('casey@example.com', mail.getToAddresses()[0]);
    Assert.areEqual('Recalled: Master Services Agreement', mail.getSubject());
    Assert.isTrue(mail.getPlainTextBody().contains('Wrong version attached'));

    List<SignZero_Audit_Trail__c> events = [
      SELECT Details__c
      FROM SignZero_Audit_Trail__c
      WHERE Event_Type__c = 'Recalled'
    ];
    Assert.areEqual(2, events.size(), 'one Recalled event per signer');
    Assert.isTrue(
      events[0]
        .Details__c.startsWith(
          'Recalled by ' +
            UserInfo.getName() +
            ' (' +
            UserInfo.getUserName() +
            ')'
        ),
      events[0].Details__c
    );
    Assert.isTrue(events[0].Details__c.endsWith(': Wrong version attached'));
    Assert.isTrue(SignZeroAuditService.verifyChain(requestId));

    // The link stops working at once, and the signer is told why.
    assertGatewayError(TOKEN_A, null, System.Label.SZ_Err_Recalled);
    assertGatewayError(TOKEN_A, SIGNED_PDF, System.Label.SZ_Err_Recalled);
    try {
      SignZeroGatewayController.declineToSign(TOKEN_A, 'late', 'x');
      Assert.fail('a recalled envelope cannot be declined');
    } catch (AuraHandledException e) {
      Assert.areEqual(System.Label.SZ_Err_Recalled, e.getMessage());
    }

    // A progression job still in the queue does not invite the next signer.
    new SignZeroProgressionJob(new Set<Id>{ requestId }, new Set<Id>())
      .execute(null);
    SignZero_Recipient__c next = recipient(requestId, 2);
    Assert.areEqual('Voided', next.Status__c);
    Assert.isNull(next.Token_Hash__c);
    Assert.areEqual(1, SignZeroNotifier.sentInTest.size());
  }

  @IsTest
  static void recallIsRefusedOnceTheEnvelopeIsClosed() {
    Id requestId = dispatchTwoSigners();
    for (String status : new List<String>{ 'Completed', 'Declined' }) {
      SignZeroRecordGuard.processUpdate = true;
      update as system new SignZero_Request__c(
        Id = requestId,
        Status__c = status
      );
      assertRecallRefused(
        requestId,
        status == 'Completed'
          ? System.Label.SZ_Recall_Err_Completed
          : System.Label.SZ_Recall_Err_Declined
      );
    }
    SignZeroRecordGuard.processUpdate = true;
    update as system new SignZero_Request__c(
      Id = requestId,
      Status__c = 'Out for Signature'
    );

    SignZeroRecallController.recall(requestId, null);
    assertRecallRefused(requestId, System.Label.SZ_Recall_Err_Already);
    Assert.isNull(
      [SELECT Recall_Reason__c FROM SignZero_Request__c WHERE Id = :requestId]
      .Recall_Reason__c
    );
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM SignZero_Audit_Trail__c
        WHERE Event_Type__c = 'Recalled'
      ],
      'a refused recall writes nothing'
    );
  }

  private static void assertRecallRefused(Id requestId, String expected) {
    try {
      SignZeroRecallController.recall(requestId, 'again');
      Assert.fail('expected the recall to be refused: ' + expected);
    } catch (AuraHandledException e) {
      Assert.areEqual(expected, e.getMessage());
    }
  }

  @IsTest
  static void recallStandsWhenTheCancellationEmailFails() {
    Id requestId = dispatchTwoSigners();
    SignZeroNotifier.failSendsInTest = true;

    SignZeroRecallController.Result result = SignZeroRecallController.recall(
      requestId,
      null
    );

    Assert.areEqual(0, result.notified);
    Assert.areEqual(
      String.format(
        System.Label.SZ_Recall_Email_Failed,
        new List<Object>{ 'SINGLE_EMAIL_LIMIT_EXCEEDED (simulated)' }
      ),
      result.warning
    );
    SignZero_Request__c env = [
      SELECT Status__c, Error_Message__c
      FROM SignZero_Request__c
      WHERE Id = :requestId
    ];
    Assert.areEqual('Voided', env.Status__c);
    Assert.areEqual(result.warning, env.Error_Message__c);
  }

  @IsTest
  static void recallNeedsEditAccessToTheEnvelope() {
    Id requestId = dispatchTwoSigners();
    User sender = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User']
      .Id,
      LastName = 'Reader',
      Email = 'reader@example.com',
      Username = 'reader.' + System.currentTimeMillis() + '@signzero.test',
      Alias = 'reader',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert sender;
      insert new PermissionSetAssignment(
        AssigneeId = sender.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'SignZero_User'
        ]
        .Id
      );
    }

    System.runAs(sender) {
      assertRecallRefused(requestId, System.Label.SZ_Recall_Err_Not_Found);
    }
    insert new SignZero_Request__Share(
      ParentId = requestId,
      UserOrGroupId = sender.Id,
      AccessLevel = 'Read',
      RowCause = 'Manual'
    );
    System.runAs(sender) {
      assertRecallRefused(requestId, System.Label.SZ_Recall_Err_No_Access);
    }
    Assert.areEqual(
      'Out for Signature',
      [SELECT Status__c FROM SignZero_Request__c WHERE Id = :requestId]
      .Status__c
    );
  }

  private static void assertBlocked(SObject row, String expected) {
    Database.SaveResult result = Database.update(
      row,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Assert.isFalse(result.isSuccess(), 'expected the edit to be blocked');
    Assert.isTrue(
      result.getErrors()[0].getMessage().contains(expected),
      result.getErrors()[0].getMessage()
    );
  }

  @IsTest
  static void appenderKeepsExecutedBytesAndAddsCertificatePages() {
    Blob executed = Blob.toPdf('<p>Agreement</p>');
    Blob certificate = Blob.toPdf('<p>Certificate of Completion</p>');

    Blob combined = SignZeroPdfAppender.append(executed, certificate);

    String combinedHex = EncodingUtil.convertToHex(combined);
    Assert.isTrue(
      combinedHex.startsWith(EncodingUtil.convertToHex(executed)),
      'the executed agreement must be the unchanged prefix so its hash still verifies'
    );
    Assert.isTrue(
      combinedHex.contains(
        EncodingUtil.convertToHex(Blob.valueOf('/Type/Pages/Kids['))
      )
    );
    // The result is itself a valid input, which proves its cross-reference chain parses.
    Assert.isTrue(
      SignZeroPdfAppender.append(combined, certificate).size() > combined.size()
    );
  }

  @IsTest
  static void appenderRejectsCompressedCrossReferences() {
    Blob xrefStream = Blob.valueOf(
      '%PDF-1.7\n1 0 obj\n<</Type/XRef>>\nendobj\nstartxref\n9\n%%EOF\n'
    );
    try {
      SignZeroPdfAppender.append(xrefStream, Blob.toPdf('<p>x</p>'));
      Assert.fail('expected UnsupportedPdfException');
    } catch (SignZeroPdfAppender.UnsupportedPdfException e) {
      Assert.isTrue(e.getMessage().contains('not supported'), e.getMessage());
    }
  }

  @IsTest
  static void certificateControllerBuildsRows() {
    Id requestId = dispatchTwoSigners();
    Test.setCurrentPage(Page.SignZeroCertificate);
    ApexPages.currentPage().getParameters().put('id', requestId);
    ApexPages.currentPage().getParameters().put('postHash', 'abc');
    ApexPages.currentPage().getParameters().put('pki', '1');

    SignZeroCertificateController ctrl = new SignZeroCertificateController();

    Assert.areEqual(2, ctrl.signers.size());
    Assert.areEqual('abc', ctrl.postSignHash);
    Assert.isTrue(ctrl.pkiApplied);
    Assert.isTrue(ctrl.ledgerIntact);
    Assert.areEqual(1, ctrl.events.size());
    Assert.areEqual('—', ctrl.signers[1].sentAt);
    String html = ctrl.toHtml();
    Assert.isTrue(
      html.contains('Casey Customer') &&
      html.contains('Organisation Digital Signature')
    );
  }
}
