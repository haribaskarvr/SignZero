/**
 * @description Stops people from changing SignZero evidence by hand (UI, inline edit, Data Loader, API). SignZero's own
 *   processing sets processUpdate before it writes; any other change to a protected field is rejected.
 */
public without sharing class SignZeroRecordGuard {
  /** @description True while SignZero's own processing is writing, for the rest of the transaction. */
  public static Boolean processUpdate = false;

  /**
   * @description Lets SignZero's own processing change protected fields for the rest of the transaction.
   */
  public static void markProcessUpdate() {
    processUpdate = true;
  }

  /**
   * @description Before insert and update on envelopes: blocks manual creation, edits to protected fields and status
   *   changes.
   * @param rows Trigger.new
   * @param oldMap Trigger.oldMap, null on insert
   */
  public static void guardRequests(
    List<SignZero_Request__c> rows,
    Map<Id, SignZero_Request__c> oldMap
  ) {
    for (SignZero_Request__c row : rows) {
      if (oldMap == null) {
        if (!processUpdate) {
          row.addError(System.Label.SZ_Guard_Create_Envelope);
        }
        continue;
      }
      SignZero_Request__c old = oldMap.get(row.Id);
      if (processUpdate) {
        continue;
      }
      String changed = firstChanged(row, old, SignZeroConstants.GUARDED_REQUEST_FIELDS);
      if (changed != null) {
        row.addError(changed, System.Label.SZ_Guard_Field_Locked);
      }
      // Voiding goes through Recall Envelope, which also closes links, emails signers and writes the audit trail.
      if (row.Status__c != old.Status__c) {
        row.Status__c.addError(System.Label.SZ_Guard_Status_Locked);
      }
    }
  }

  /**
   * @description Before delete on envelopes: sent envelopes keep their audit trail.
   * @param rows Trigger.old
   */
  public static void guardRequestDeletes(List<SignZero_Request__c> rows) {
    for (SignZero_Request__c row : rows) {
      if (SignZeroConstants.ENVELOPE_SENT.contains(row.Status__c)) {
        row.addError(System.Label.SZ_Guard_Envelope_Delete);
      }
    }
  }

  /**
   * @description Before insert and update on signers: blocks manual creation, evidence edits and identity changes after
   *   sending.
   * @param rows Trigger.new
   * @param oldMap Trigger.oldMap, null on insert
   */
  public static void guardRecipients(
    List<SignZero_Recipient__c> rows,
    Map<Id, SignZero_Recipient__c> oldMap
  ) {
    if (processUpdate) {
      return;
    }
    for (SignZero_Recipient__c row : rows) {
      if (oldMap == null) {
        row.addError(System.Label.SZ_Guard_Create_Signer);
        continue;
      }
      SignZero_Recipient__c old = oldMap.get(row.Id);
      String changed = firstChanged(row, old, SignZeroConstants.GUARDED_RECIPIENT_FIELDS);
      if (changed != null) {
        row.addError(changed, System.Label.SZ_Guard_Field_Locked);
      } else if (
        old.Status__c != SignZeroConstants.SIGNER_PENDING &&
        firstChanged(row, old, SignZeroConstants.SIGNER_IDENTITY_FIELDS) != null
      ) {
        row.addError(System.Label.SZ_Guard_Signer_Locked);
      }
    }
  }

  /**
   * @description Before delete on signers: invited signers keep their audit trail.
   * @param rows Trigger.old
   */
  public static void guardRecipientDeletes(List<SignZero_Recipient__c> rows) {
    if (processUpdate) {
      return;
    }
    for (SignZero_Recipient__c row : rows) {
      if (row.Status__c != SignZeroConstants.SIGNER_PENDING) {
        row.addError(System.Label.SZ_Guard_Signer_Delete);
      }
    }
  }

  /**
   * @description Finds the first field that changed.
   * @param row the new record
   * @param old the old record
   * @param fields the fields to compare
   * @return the first changed field's name, or null
   */
  private static String firstChanged(
    SObject row,
    SObject old,
    List<String> fields
  ) {
    for (String f : fields) {
      if (row.get(f) != old.get(f)) {
        return f;
      }
    }
    return null;
  }
}
