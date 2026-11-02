/**
 * @description Append-only, hash-chained audit ledger for SignZero envelopes. Each event's hash covers its own fields
 *   and the previous event's hash, so editing or removing an event breaks the chain. Runs without sharing because the
 *   guest-user signing gateway calls it.
 */
public without sharing class SignZeroAuditService {
  /**
   * @description One audit event to append to the ledger.
   */
  public class Entry {
    /** @description Signer the event is filed under. */
    public Id recipientId;
    /** @description Envelope whose hash chain the event extends. */
    public Id requestId;
    /** @description A value of the Event Type picklist (see the EVENT_* constants). */
    public String eventType;
    /** @description Source IP of the person who caused the event, if known. */
    public String ipAddress;
    /** @description Browser of the person who caused the event, if known. */
    public String userAgent;
    /** @description SHA-256 of the document at the time of the event, if relevant. */
    public String documentHash;
    /** @description Free-text details shown on the Certificate of Completion. */
    public String details;

    /**
     * @description Creates an event; set the optional fields before logging it.
     * @param recipientId signer the event is filed under
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
   * @description Appends events in order, chaining each to the previous event of the same envelope.
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
   * @description Appends a single event.
   * @param e the event to write
   */
  public static void logOne(Entry e) {
    log(new List<Entry>{ e });
  }

  /**
   * @description Recomputes an envelope's hash chain to check that no event was altered or removed.
   * @param requestId the envelope to check
   * @return true when the chain is intact, false otherwise
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
   * @description Returns an envelope's audit events in chain order.
   * @param requestId the envelope
   * @return its audit rows, oldest first
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
   * @description Returns the source IP of the current user's session.
   * @return the IP, or null where no session can be read (tests, async jobs, site guest users)
   */
  public static String clientIp() {
    // getCurrentSession() throws an uncatchable exception when there is no session.
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
      return null;
    }
  }

  /**
   * @description Finds the newest event hash of each envelope, to chain new events onto.
   * @param requestIds the envelopes
   * @return envelope Id to its latest event hash; envelopes without events are missing
   */
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

  /**
   * @description Computes an audit row's chained SHA-256 hash.
   * @param row the audit row, including its previous event hash
   * @return the hash, as lower-case hex
   */
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

  /**
   * @description Treats null as an empty string, so hashes are stable.
   * @param s any text
   * @return s, or '' when null
   */
  private static String nz(String s) {
    return s == null ? '' : s;
  }
}
