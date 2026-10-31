/**
 * Certificate of Completion data. Backs the SignZeroCertificate Visualforce page for internal users, and
 * renders the same certificate as HTML through Blob.toPdf() during sealing. Sealing runs as the platform
 * event user, which cannot open Visualforce pages, and passes the executed hash in because the
 * certificate is rendered before the envelope record is updated.
 * Inherited sharing: with sharing as a page controller, without sharing when called by SignZeroSealService.
 * Queries use system mode for field access because sealing runs as the Automated Process user.
 */
public inherited sharing class SignZeroCertificateController {
  /** One signer, as listed on the certificate. */
  public class SignerRow {
    /** Signer's name. */
    public String name { get; set; }
    /** Signer's email address. */
    public String email { get; set; }
    /** Signer role, e.g. Customer. */
    public String role { get; set; }
    /** Signing status, including reassignment or delegation. */
    public String status { get; set; }
    /** Last IP address the signer used. */
    public String ip { get; set; }
    /** How the signer was authenticated. */
    public String authMethod { get; set; }
    /** How the signature was adopted (typed, drawn or uploaded). */
    public String signatureMethod { get; set; }
    /** Signer's browser. */
    public String userAgent { get; set; }
    /** When the invitation was sent, in GMT. */
    public String sentAt { get; set; }
    /** When the signer first opened the document, in GMT. */
    public String viewedAt { get; set; }
    /** When the signer accepted the electronic records disclosure, in GMT. */
    public String consentedAt { get; set; }
    /** When the signer signed, in GMT. */
    public String signedAt { get; set; }
  }

  /** One audit event, as listed on the certificate. */
  public class EventRow {
    /** When the event happened, in GMT. */
    public String timestamp { get; set; }
    /** Signer the event belongs to. */
    public String signer { get; set; }
    /** What happened. */
    public String eventType { get; set; }
    /** IP address recorded with the event. */
    public String ip { get; set; }
    /** Event details. */
    public String details { get; set; }
    /** The event's hash in the audit chain. */
    public String eventHash { get; set; }
  }

  /** The envelope the certificate is for. */
  public SignZero_Request__c sigRequest { get; set; }
  /** SHA-256 hash of the executed document. */
  public String postSignHash { get; set; }
  /** When the certificate was generated, in GMT. */
  public String generatedAt { get; set; }
  /** Whether the audit chain verified. */
  public Boolean ledgerIntact { get; set; }
  /** Whether the document hash was signed with an org certificate. */
  public Boolean pkiApplied { get; set; }
  /** One row per signer. */
  public List<SignerRow> signers { get; set; }
  /** The audit trail, oldest first. */
  public List<EventRow> events { get; set; }

  /** Page controller: reads id, postHash and pki (1 or blank) from the page URL. */
  public SignZeroCertificateController() {
    Map<String, String> params = ApexPages.currentPage().getParameters();
    load(params.get('id'), params.get('postHash'), params.get('pki') == '1');
  }

  private SignZeroCertificateController(Id reqId, String postHash, Boolean pki) {
    load(reqId, postHash, pki);
  }

  private void load(Id reqId, String postHash, Boolean pki) {
    signers = new List<SignerRow>();
    events = new List<EventRow>();
    generatedAt = utc(Datetime.now());
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
      row.status = r.Status__c == 'Reassigned' &&
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
   * Renders the certificate as a PDF, for sealing.
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
   * Same layout as SignZeroCertificate.page, as a standalone HTML document.
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
      '<div class="header"><div class="title">Certificate of Completion</div>',
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

  private static String row(String label, String value, String cssClass) {
    return '<tr><td class="label">' +
      label +
      '</td><td class="' +
      cssClass +
      '">' +
      value +
      '</td></tr>';
  }

  private static String h(String value) {
    return value == null ? '' : value.escapeHtml4();
  }

  private static String utc(Datetime value) {
    return value == null
      ? '—'
      : value.formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC';
  }
}
