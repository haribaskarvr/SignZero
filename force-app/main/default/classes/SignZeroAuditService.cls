/**
 * Append-only, hash-chained audit ledger. Every event's hash covers its own fields plus the
 * previous event hash for the same envelope, so editing or removing an event breaks the chain.
 * Runs without sharing because it is called from the guest-user signing gateway.
 */
public without sharing class SignZeroAuditService {
  /** One event to append to the ledger. */
  public class Entry {
    public Id recipientId;
    public Id requestId;
    public String eventType;
    public String ipAddress;
    public String userAgent;
    public String documentHash;
    public String details;

    /**
     * Describes one event; set the optional fields before logging it.
     * @param recipientId signer the event belongs to (every event is filed under a signer)
     * @param requestId envelope whose hash chain the event extends
     * @param eventType a value of the Event Type picklist
     */
    public Entry(Id recipientId, Id requestId, String eventType) {
      this.recipientId = recipientId;
      this.requestId = requestId;
      this.eventType = eventType;
    }
  }

  /**
   * Appends events, chaining each to the previous event of the same envelope.
   * @param entries events to write, in order
   * @return the inserted audit rows
   */
  public static List<SignZero_Audit_Trail__c> log(List<Entry> entries) {
    SignZeroRecordGuard.markProcessUpdate();
    if (entries == null || entries.isEmpty()) {
      return new List<SignZero_Audit_Trail__c>();
    }
    Set<Id> requestIds = new Set<Id>();
    for (Entry e : entries) {
      requestIds.add(e.requestId);
    }
    Map<Id, String> lastHashByRequest = latestHashes(requestIds);

    Datetime now = Datetime.now();
    List<SignZero_Audit_Trail__c> rows = new List<SignZero_Audit_Trail__c>();
    for (Entry e : entries) {
      SignZero_Audit_Trail__c row = new SignZero_Audit_Trail__c(
        SignZero_Recipient__c = e.recipientId,
        Event_Type__c = e.eventType,
        Timestamp_UTC__c = now,
        IP_Address__c = e.ipAddress == null ? null : e.ipAddress.left(45),
        User_Agent__c = e.userAgent == null ? null : e.userAgent.left(255),
        Document_Hash__c = e.documentHash,
        Details__c = e.details == null ? null : e.details.left(255),
        Previous_Event_Hash__c = lastHashByRequest.get(e.requestId)
      );
      row.Event_Hash__c = hashOf(row);
      lastHashByRequest.put(e.requestId, row.Event_Hash__c);
      rows.add(row);
    }
    insert as system rows;
    return rows;
  }

  /**
   * Appends a single event.
   * @param e the event to write
   */
  public static void logOne(Entry e) {
    log(new List<Entry>{ e });
  }

  /**
   * Recomputes the chain for an envelope.
   * @param requestId the envelope to check
   * @return false if any event was altered or removed
   */
  public static Boolean verifyChain(Id requestId) {
    String previous = null;
    for (SignZero_Audit_Trail__c row : orderedEvents(requestId)) {
      if (
        row.Previous_Event_Hash__c != previous ||
        row.Event_Hash__c != hashOf(row)
      ) {
        return false;
      }
      previous = row.Event_Hash__c;
    }
    return true;
  }

  /**
   * The envelope's events, oldest first.
   * @param requestId the envelope
   * @return its audit rows in chain order
   */
  public static List<SignZero_Audit_Trail__c> orderedEvents(Id requestId) {
    return [
      SELECT
        Id,
        Name,
        SignZero_Recipient__c,
        SignZero_Recipient__r.Name,
        Event_Type__c,
        Timestamp_UTC__c,
        IP_Address__c,
        User_Agent__c,
        Document_Hash__c,
        Details__c,
        Previous_Event_Hash__c,
        Event_Hash__c
      FROM SignZero_Audit_Trail__c
      WHERE SignZero_Recipient__r.SignZero_Request__c = :requestId
      WITH SYSTEM_MODE
      ORDER BY Timestamp_UTC__c ASC, Name ASC
    ];
  }

  /**
   * Source IP of the current user's session, for the audit trail.
   * @return the IP, or null where no session can be read (tests, async jobs, site guest users)
   */
  public static String clientIp() {
    // With no session (tests, async, and site guest users, who never get one), getCurrentSession()
    // throws an exception that cannot be caught, so the source IP is unavailable in those contexts.
    if (
      Test.isRunningTest() ||
      UserInfo.getUserType() == 'Guest' ||
      System.isQueueable() ||
      System.isFuture() ||
      System.isBatch() ||
      System.isScheduled()
    ) {
      return null;
    }
    try {
      Map<String, String> session = Auth.SessionManagement.getCurrentSession();
      return session == null ? null : session.get('SourceIp');
    } catch (Exception e) {
      // Guest and async contexts may have no session to read.
      return null;
    }
  }

  private static Map<Id, String> latestHashes(Set<Id> requestIds) {
    Map<Id, String> result = new Map<Id, String>();
    for (SignZero_Audit_Trail__c row : [
      SELECT Event_Hash__c, SignZero_Recipient__r.SignZero_Request__c
      FROM SignZero_Audit_Trail__c
      WHERE SignZero_Recipient__r.SignZero_Request__c IN :requestIds
      WITH SYSTEM_MODE
      ORDER BY Timestamp_UTC__c DESC, Name DESC
    ]) {
      Id requestId = row.SignZero_Recipient__r.SignZero_Request__c;
      if (!result.containsKey(requestId)) {
        result.put(requestId, row.Event_Hash__c);
      }
    }
    return result;
  }

  private static String hashOf(SignZero_Audit_Trail__c row) {
    String material = String.join(
      new List<String>{
        nz(row.Previous_Event_Hash__c),
        String.valueOf(row.SignZero_Recipient__c).left(15),
        nz(row.Event_Type__c),
        row.Timestamp_UTC__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
        nz(row.IP_Address__c),
        nz(row.User_Agent__c),
        nz(row.Document_Hash__c),
        nz(row.Details__c)
      },
      '|'
    );
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(material))
    );
  }

  private static String nz(String s) {
    return s == null ? '' : s;
  }
}
