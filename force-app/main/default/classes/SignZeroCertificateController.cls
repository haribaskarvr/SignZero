/**
 * @description Certificate of Completion. Backs the SignZeroCertificate page and renders the same certificate through
 *   Blob.toPdf() during sealing, which runs as the Automated Process user; hence system-mode queries and inherited
 *   sharing.
 */
public inherited sharing class SignZeroCertificateController {
  /**
   * @description One signer as listed on the certificate. Times are GMT.
   */
  public class SignerRow {
    /** @description Signer's name. */
    public String name { get; set; }
    /** @description Signer's email address. */
    public String email { get; set; }
    /** @description Signer role, e.g. Customer. */
    public String role { get; set; }
    /** @description Signing status, including reassignment. */
    public String status { get; set; }
    /** @description Last IP address the signer used. */
    public String ip { get; set; }
    /** @description How the signer was authenticated. */
    public String authMethod { get; set; }
    /** @description How the signature was adopted: typed, drawn or uploaded. */
    public String signatureMethod { get; set; }
    /** @description Signer's browser. */
    public String userAgent { get; set; }
    /** @description When the invitation was sent. */
    public String sentAt { get; set; }
    /** @description When the signer first opened the document. */
    public String viewedAt { get; set; }
    /** @description When the signer accepted the electronic records disclosure. */
    public String consentedAt { get; set; }
    /** @description When the signer signed. */
    public String signedAt { get; set; }
  }

  /**
   * @description One audit event as listed on the certificate. Times are GMT.
   */
  public class EventRow {
    /** @description When the event happened. */
    public String timestamp { get; set; }
    /** @description Signer the event belongs to. */
    public String signer { get; set; }
    /** @description What happened. */
    public String eventType { get; set; }
    /** @description IP address recorded with the event. */
    public String ip { get; set; }
    /** @description Event details. */
    public String details { get; set; }
    /** @description The event's hash in the audit chain. */
    public String eventHash { get; set; }
  }

  /** @description The envelope the certificate is for. */
  public SignZero_Request__c sigRequest { get; set; }
  /** @description SHA-256 of the executed document. */
  public String postSignHash { get; set; }
  /** @description When the certificate was generated, in GMT. */
  public String generatedAt { get; set; }
  /** @description Company logo (https only), or null. */
  public String logoUrl { get; set; }
  /** @description Whether the audit chain verified. */
  public Boolean ledgerIntact { get; set; }
  /** @description Whether the document hash was signed with an org certificate. */
  public Boolean pkiApplied { get; set; }
  /** @description One row per signer. */
  public List<SignerRow> signers { get; set; }
  /** @description The audit trail, oldest first. */
  public List<EventRow> events { get; set; }

  /**
   * @description Page controller: reads id, postHash and pki (1 or blank) from the page URL.
   */
  public SignZeroCertificateController() {
    Map<String, String> params = ApexPages.currentPage().getParameters();
    load(params.get('id'), params.get('postHash'), params.get('pki') == '1');
  }

  /**
   * @description Builds the certificate for sealing.
   * @param reqId the envelope
   * @param postHash SHA-256 of the executed document
   * @param pki whether the hash was signed with an org certificate
   */
  private SignZeroCertificateController(Id reqId, String postHash, Boolean pki) {
    load(reqId, postHash, pki);
  }

  /**
   * @description Loads the envelope, signers and audit trail into the certificate's properties.
   * @param reqId the envelope; nothing is loaded when null
   * @param postHash SHA-256 of the executed document
   * @param pki whether the hash was signed with an org certificate
   */
  private void load(Id reqId, String postHash, Boolean pki) {
    signers = new List<SignerRow>();
    events = new List<EventRow>();
    generatedAt = utc(Datetime.now());
    String logo = SignZeroSettings.branding().get('logoUrl');
    logoUrl = String.isNotBlank(logo) && logo.startsWithIgnoreCase('https://')
      ? logo
      : null;
    if (reqId == null) {
      return;
    }
    sigRequest = [
      SELECT
        Id,
        Name,
        Document_Name__c,
        Source_Record_Id__c,
        Pre_Sign_Hash__c,
        Post_Sign_Hash__c,
        PKI_Signature__c
      FROM SignZero_Request__c
      WHERE Id = :reqId
      WITH SYSTEM_MODE
    ];
    postSignHash = String.isNotBlank(postHash)
      ? postHash
      : sigRequest.Post_Sign_Hash__c;
    pkiApplied = pki == true || String.isNotBlank(sigRequest.PKI_Signature__c);
    ledgerIntact = SignZeroAuditService.verifyChain(reqId);

    for (SignZero_Recipient__c r : [
      SELECT
        Name,
        Email__c,
        Signer_Role__c,
        Status__c,
        Last_Known_IP__c,
        Auth_Method__c,
        Signature_Method__c,
        User_Agent__c,
        Reassigned_To__r.Name,
        Reassigned_To__r.Email__c,
        Sent_At__c,
        Viewed_At__c,
        Consented_At__c,
        Signed_At__c
      FROM SignZero_Recipient__c
      WHERE SignZero_Request__c = :reqId
      WITH SYSTEM_MODE
      ORDER BY Routing_Order__c ASC
    ]) {
      SignerRow row = new SignerRow();
      row.name = r.Name;
      row.email = r.Email__c;
      row.role = r.Signer_Role__c;
      row.status = r.Status__c == SignZeroConstants.SIGNER_REASSIGNED &&
        r.Reassigned_To__r != null
        ? 'Reassigned to ' +
          r.Reassigned_To__r.Name +
          ' (' +
          r.Reassigned_To__r.Email__c +
          ')'
        : r.Status__c;
      row.ip = String.isBlank(r.Last_Known_IP__c)
        ? 'Not available'
        : r.Last_Known_IP__c;
      row.authMethod = r.Auth_Method__c;
      row.signatureMethod = String.isBlank(r.Signature_Method__c)
        ? '—'
        : r.Signature_Method__c;
      row.userAgent = r.User_Agent__c;
      row.sentAt = utc(r.Sent_At__c);
      row.viewedAt = utc(r.Viewed_At__c);
      row.consentedAt = utc(r.Consented_At__c);
      row.signedAt = utc(r.Signed_At__c);
      signers.add(row);
    }
    for (
      SignZero_Audit_Trail__c e : SignZeroAuditService.orderedEvents(reqId)
    ) {
      EventRow row = new EventRow();
      row.timestamp = utc(e.Timestamp_UTC__c);
      row.signer = e.SignZero_Recipient__r.Name;
      row.eventType = e.Event_Type__c;
      row.ip = e.IP_Address__c;
      row.details = e.Details__c;
      row.eventHash = e.Event_Hash__c;
      events.add(row);
    }
  }

  /**
   * @description Renders the certificate as a PDF, for sealing.
   * @param signatureRequestId the envelope
   * @param postSignHash hash of the executed document, passed in because the envelope is not updated yet
   * @param pkiApplied whether the hash was signed with an org certificate
   * @return the certificate PDF
   */
  public static Blob generateCertificatePdfBlob(
    Id signatureRequestId,
    String postSignHash,
    Boolean pkiApplied
  ) {
    return Blob.toPdf(
      new SignZeroCertificateController(
          signatureRequestId,
          postSignHash,
          pkiApplied
        )
        .toHtml()
    );
  }

  /**
   * @description Renders the certificate as a standalone HTML document, with the same layout as
   *   SignZeroCertificate.page.
   * @return the certificate HTML
   */
  @TestVisible
  private String toHtml() {
    List<String> out = new List<String>{
      '<html><head><style>',
      '@page { size: letter; margin: 16mm; }',
      'body { font-family: Helvetica, Arial, sans-serif; font-size: 9.5pt; color: #181818; }',
      '.header { border-bottom: 2px solid #0176d3; padding-bottom: 8px; margin-bottom: 14px; }',
      '.title { font-size: 18pt; font-weight: bold; color: #0176d3; }',
      '.sub { margin: 4px 0 0; color: #555; }',
      'h3 { margin: 18px 0 6px; color: #0176d3; font-size: 11pt; }',
      'table { width: 100%; border-collapse: collapse; }',
      'td, th { padding: 4px 5px; border-bottom: 1px solid #ddd; vertical-align: top; text-align: left; }',
      'th { background-color: #f3f3f3; font-size: 8.5pt; }',
      '.label { font-weight: bold; width: 26%; color: #444; }',
      '.hash { font-family: Courier, monospace; font-size: 7.5pt; word-wrap: break-word; }',
      '.small { font-size: 7.5pt; color: #555; }',
      '.ok { color: #2e844a; font-weight: bold; } .bad { color: #ba0517; font-weight: bold; }',
      '</style></head><body>',
      '<div class="header">' +
      (logoUrl == null
        ? ''
        : '<img src="' + h(logoUrl) + '" style="height:40px" alt="" />') +
      '<div class="title">Certificate of Completion</div>',
      '<p class="sub">Envelope ' +
      h(sigRequest.Name) +
      ' &middot; Generated ' +
      h(generatedAt) +
      '</p></div>',
      '<table>',
      row('Document', h(sigRequest.Document_Name__c), ''),
      row('Source record', h(sigRequest.Source_Record_Id__c), ''),
      row('Original SHA-256', h(sigRequest.Pre_Sign_Hash__c), 'hash'),
      row('Executed SHA-256', h(postSignHash), 'hash'),
      row(
        'Audit ledger integrity',
        ledgerIntact
          ? '<span class="ok">Verified: hash chain intact</span>'
          : '<span class="bad">FAILED: audit chain does not verify</span>',
        ''
      ),
      '</table>',
      '<h3>Signers</h3><table><tr><th>Signer</th><th>Authentication</th><th>Timestamps</th></tr>'
    };
    for (SignerRow r : signers) {
      out.add(
        '<tr><td><strong>' +
          h(r.name) +
          '</strong><br/>' +
          h(r.email) +
          '<br/>Role: ' +
          h(r.role) +
          '<br/>Status: ' +
          h(r.status) +
          '</td><td>' +
          h(r.authMethod) +
          '<br/>Signature: ' +
          h(r.signatureMethod) +
          '<br/>IP: ' +
          h(r.ip) +
          '<br/><span class="small">' +
          h(r.userAgent) +
          '</span></td><td>Sent: ' +
          h(r.sentAt) +
          '<br/>Viewed: ' +
          h(r.viewedAt) +
          '<br/>Consented: ' +
          h(r.consentedAt) +
          '<br/>Signed: ' +
          h(r.signedAt) +
          '</td></tr>'
      );
    }
    out.add(
      '</table><h3>Audit Ledger</h3><table><tr><th>Time</th><th>Signer</th><th>Event</th><th>IP</th><th>Details / Event hash</th></tr>'
    );
    for (EventRow e : events) {
      out.add(
        '<tr><td>' +
          h(e.timestamp) +
          '</td><td>' +
          h(e.signer) +
          '</td><td>' +
          h(e.eventType) +
          '</td><td>' +
          h(e.ip) +
          '</td><td>' +
          h(e.details) +
          '<br/><span class="hash">' +
          h(e.eventHash) +
          '</span></td></tr>'
      );
    }
    out.add('</table>');
    if (pkiApplied) {
      out.add(
        '<h3>Organisation Digital Signature</h3><p class="small">The executed PDF bytes were signed with RSA-SHA256 ' +
          'using the organisation\'s X.509 certificate. The detached signature is stored on envelope ' +
          h(sigRequest.Name) +
          '.</p>'
      );
    }
    out.add('</body></html>');
    return String.join(out, '');
  }

  /**
   * @description Builds one label/value table row.
   * @param label the label, already HTML-safe
   * @param value the value, already HTML-safe
   * @param cssClass CSS class for the value cell
   * @return the row HTML
   */
  private static String row(String label, String value, String cssClass) {
    return '<tr><td class="label">' +
      label +
      '</td><td class="' +
      cssClass +
      '">' +
      value +
      '</td></tr>';
  }

  /**
   * @description Escapes text for HTML.
   * @param value any text
   * @return the escaped text, or '' when null
   */
  private static String h(String value) {
    return value == null ? '' : value.escapeHtml4();
  }

  /**
   * @description Formats a time for the certificate.
   * @param value the time
   * @return "yyyy-MM-dd HH:mm:ss UTC", or a dash when null
   */
  private static String utc(Datetime value) {
    return value == null
      ? '—'
      : value.formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC';
  }
}
