// See SignZeroRecordGuard.
trigger SignZeroRecipientTrigger on SignZero_Recipient__c (before insert, before update, before delete) {
    if (Trigger.isDelete) {
        SignZeroRecordGuard.guardRecipientDeletes(Trigger.old);
    } else {
        SignZeroRecordGuard.guardRecipients(Trigger.new, Trigger.oldMap);
    }
}