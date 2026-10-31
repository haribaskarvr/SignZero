// Envelope evidence is maintained by SignZero only; see SignZeroRecordGuard.
trigger SignZeroRequestTrigger on SignZero_Request__c (before insert, before update, before delete) {
    if (Trigger.isDelete) {
        SignZeroRecordGuard.guardRequestDeletes(Trigger.old);
    } else {
        SignZeroRecordGuard.guardRequests(Trigger.new, Trigger.oldMap);
    }
}