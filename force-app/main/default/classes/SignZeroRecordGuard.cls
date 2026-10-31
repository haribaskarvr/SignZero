/**
 * Stops people from changing SignZero evidence by hand (UI, inline edit, Data Loader, API). The SignZero
 * process sets processUpdate before it writes; any other change to a protected field is rejected.
 */
public without sharing class SignZeroRecordGuard {
  /** Signer statuses that still owe a signature. */
  public static final Set<String> AWAITING = new Set<String>{
    'Pending',
    'Sent',
    'Viewed',
    'Consented'
  };

  /** Set by SignZero's own services for the rest of the transaction. */
  public static Boolean processUpdate = false;

  private static final List<String> REQUEST_LOCKED = new List<String>{
    'Source_Record_Id__c',
    'Content_Document_Id__c',
    'Related_Record_Ids__c',
    'Pre_Sign_Hash__c',
    'Post_Sign_Hash__c',
    'Working_Copy_Hash__c',
    'Working_Copy_Id__c',
    'PKI_Signature__c',
    'Final_Document_Version_Id__c',
    'Certificate_Version_Id__c',
    'Combined_Document_Version_Id__c',
    'Completed_At__c',
    'Error_Message__c',
    'Recall_Reason__c'
  };
  private static final List<String> RECIPIENT_LOCKED = new List<String>{
    'Token_Hash__c',
    'Token_Expires_At__c',
    'Status__c',
    'Auth_Method__c',
    'Signature_Method__c',
    'Last_Known_IP__c',
    'User_Agent__c',
    'Reassigned_To__c',
    'Reassign_Reason__c',
    'Delegated_From__c',
    'List_Order__c',
    'Sent_At__c',
    'Viewed_At__c',
    'Consented_At__c',
    'Signed_At__c',
    'Decline_Reason__c'
  };
  // Who signs can only change before the invitation goes out.
  private static final List<String> RECIPIENT_IDENTITY = new List<String>{
    'Name',
    'Email__c',
    'Signer_Role__c',
    'Routing_Order__c',
    'SignZero_Request__c'
  };
  private static final Set<String> CLOSED_ENVELOPE = new Set<String>{
    'Out for Signature',
    'Sealing',
    'Completed',
    'Declined'
  };

  /** Lets SignZero's own processing change protected fields for the rest of the transaction. */
  public static void markProcessUpdate() {
    processUpdate = true;
  }

  /**
   * Before insert and update on envelopes: blocks manual creation, edits to protected fields and status changes.
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
      String changed = firstChanged(row, old, REQUEST_LOCKED);
      if (changed != null) {
        row.addError(changed, System.Label.SZ_Guard_Field_Locked);
      }
      // Voiding goes through the Recall Envelope action, which also closes the signing links, emails the
      // signers and writes the audit trail; a plain status edit would do none of that.
      if (row.Status__c != old.Status__c) {
        row.Status__c.addError(System.Label.SZ_Guard_Status_Locked);
      }
    }
  }

  /**
   * Before delete on envelopes: sent envelopes keep their audit ledger.
   * @param rows Trigger.old
   */
  public static void guardRequestDeletes(List<SignZero_Request__c> rows) {
    for (SignZero_Request__c row : rows) {
      if (CLOSED_ENVELOPE.contains(row.Status__c)) {
        row.addError(System.Label.SZ_Guard_Envelope_Delete);
      }
    }
  }

  /**
   * Before insert and update on signers: blocks manual creation, evidence edits and identity changes after sending.
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
      String changed = firstChanged(row, old, RECIPIENT_LOCKED);
      if (changed != null) {
        row.addError(changed, System.Label.SZ_Guard_Field_Locked);
      } else if (
        old.Status__c != 'Pending' &&
        firstChanged(row, old, RECIPIENT_IDENTITY) != null
      ) {
        row.addError(System.Label.SZ_Guard_Signer_Locked);
      }
    }
  }

  /**
   * Before delete on signers: invited signers keep their audit trail.
   * @param rows Trigger.old
   */
  public static void guardRecipientDeletes(List<SignZero_Recipient__c> rows) {
    if (processUpdate) {
      return;
    }
    for (SignZero_Recipient__c row : rows) {
      if (row.Status__c != 'Pending') {
        row.addError(System.Label.SZ_Guard_Signer_Delete);
      }
    }
  }

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
