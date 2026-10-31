// The audit ledger is append-only, and only SignZero appends to it.
trigger SignZeroAuditTrailTrigger on SignZero_Audit_Trail__c (before insert, before update, before delete) {
    for (SignZero_Audit_Trail__c row : Trigger.isDelete ? Trigger.old : Trigger.new) {
        if (Trigger.isInsert) {
            if (!SignZeroRecordGuard.processUpdate) {
                row.addError(System.Label.SZ_Guard_Audit_Insert);
            }
        } else {
            row.addError(System.Label.SZ_Guard_Audit_Immutable);
        }
    }
}