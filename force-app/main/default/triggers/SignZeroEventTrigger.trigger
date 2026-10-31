trigger SignZeroEventTrigger on SignZero_Event__e (after insert) {
    SignZeroProgressionJob.handleEvents(Trigger.new);
}