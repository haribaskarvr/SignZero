/**
 * @description Emails automatic reminders to signers who have not signed, and tells the sender when a link expired.
 *   Timing comes from SignZero Settings (Reminder Schedule, First After, Repeat, Limit). Start it once with schedule();
 *   it follows later changes to Reminder Schedule by itself.
 */
public without sharing class SignZeroReminderJob implements Schedulable, Database.Batchable<SObject> {
  /**
   * @description Schedules the job from Reminder Schedule, replacing any SignZero reminder job already scheduled. An
   *   invalid expression keeps the previous schedule and throws.
   * @return the scheduled job's Id
   */
  public static Id schedule() {
    String previous;
    for (CronTrigger existing : [
      SELECT Id, CronExpression
      FROM CronTrigger
      WHERE CronJobDetail.Name = :SignZeroConstants.REMINDER_JOB_NAME
      WITH SYSTEM_MODE
    ]) {
      previous = existing.CronExpression;
      System.abortJob(existing.Id);
    }
    try {
      return System.schedule(
        SignZeroConstants.REMINDER_JOB_NAME,
        SignZeroSettings.reminderCronExpression(),
        new SignZeroReminderJob()
      );
    } catch (Exception e) {
      if (previous != null) {
        System.schedule(SignZeroConstants.REMINDER_JOB_NAME, previous, new SignZeroReminderJob());
      }
      throw e;
    }
  }

  /**
   * @description Scheduled run: reschedules if Reminder Schedule changed, then starts the reminder batch.
   * @param ctx the schedule context
   */
  public void execute(SchedulableContext ctx) {
    // Reschedule when Reminder Schedule changed, and still do this run's work.
    List<CronTrigger> current = [
      SELECT CronExpression
      FROM CronTrigger
      WHERE Id = :ctx.getTriggerId()
      WITH SYSTEM_MODE
    ];
    if (
      !current.isEmpty() &&
      current[0].CronExpression != SignZeroSettings.reminderCronExpression()
    ) {
      try {
        schedule();
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'SignZero Reminder Schedule is not a valid cron expression: ' +
          e.getMessage()
        );
      }
    }
    Database.executeBatch(new SignZeroReminderJob(), SignZeroConstants.REMINDER_BATCH_SIZE);
  }

  /**
   * @description Selects signers whose turn it is, on envelopes still out for signature.
   * @param ctx the batch context
   * @return the query locator
   */
  public Database.QueryLocator start(Database.BatchableContext ctx) {
    // Signers whose turn it is, on envelopes still out for signature.
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          Sent_At__c,
          Token_Expires_At__c,
          Reminders_Sent__c,
          Expiry_Notified_At__c,
          SignZero_Request__c,
          SignZero_Request__r.Name,
          SignZero_Request__r.OwnerId,
          SignZero_Request__r.Document_Name__c
        FROM SignZero_Recipient__c
        WHERE
          Status__c IN :SignZeroConstants.SIGNER_OPEN
          AND Token_Hash__c != NULL
          AND SignZero_Request__r.Status__c = :SignZeroConstants.ENVELOPE_OUT_FOR_SIGNATURE
      ]
    );
  }

  /**
   * @description Sends the reminders and expiry notices due for one batch.
   * @param ctx the batch context
   * @param scope the signers in this batch
   */
  public void execute(
    Database.BatchableContext ctx,
    List<SignZero_Recipient__c> scope
  ) {
    process(scope, Datetime.now());
  }

  /**
   * @description Nothing to do after the batch.
   * @param ctx the batch context
   */
  public void finish(Database.BatchableContext ctx) {
  }

  /**
   * @description Sends the reminders that are due and the expiry notices that are owed.
   * @param recipients signers whose turn it is
   * @param now the time to measure against
   */
  @TestVisible
  private static void process(
    List<SignZero_Recipient__c> recipients,
    Datetime now
  ) {
    Integer firstAfter = SignZeroSettings.reminderFirstAfterDays();
    Integer repeatDays = SignZeroSettings.reminderRepeatDays();
    Integer reminderLimit = SignZeroSettings.reminderLimit();

    Set<Id> due = new Set<Id>();
    List<SignZero_Recipient__c> expired = new List<SignZero_Recipient__c>();
    for (SignZero_Recipient__c r : recipients) {
      Integer sent = r.Reminders_Sent__c == null
        ? 0
        : r.Reminders_Sent__c.intValue();
      Boolean moreToCome = firstAfter != null && sent < reminderLimit;
      Integer wait = sent == 0 ? firstAfter : repeatDays;
      if (
        moreToCome &&
        wait != null &&
        r.Sent_At__c != null &&
        r.Sent_At__c.addDays(wait) <= now
      ) {
        due.add(r.Id);
      } else if (
        !moreToCome &&
        r.Expiry_Notified_At__c == null &&
        r.Token_Expires_At__c != null &&
        r.Token_Expires_At__c <= now
      ) {
        expired.add(r);
      }
    }

    if (!due.isEmpty()) {
      // Save new links before emailing; if sending fails, the old links keep working.
      Savepoint beforeReminders = Database.setSavepoint();
      try {
        SignZeroInvitationService.sendReminders(due);
      } catch (Exception e) {
        Database.rollback(beforeReminders);
        // The next run tries again.
        System.debug(
          LoggingLevel.WARN,
          'SignZero reminders failed: ' + e.getMessage()
        );
      }
    }

    if (!expired.isEmpty()) {
      SignZeroRecordGuard.markProcessUpdate();
      List<SignZero_Recipient__c> updates = new List<SignZero_Recipient__c>();
      for (SignZero_Recipient__c r : expired) {
        SignZero_Request__c req = r.SignZero_Request__r;
        SignZeroNotifier.bell(
          req,
          SignZeroNotifier.bellTitle(req, System.Label.SZ_Bell_Link_Expired),
          SignZeroNotifier.bellBody(
            req,
            SignZeroNotifier.fill(
              System.Label.SZ_Bell_Link_Expired_Body,
              new List<Object>{ r.Name }
            )
          )
        );
        updates.add(
          new SignZero_Recipient__c(Id = r.Id, Expiry_Notified_At__c = now)
        );
      }
      update as system updates;
    }
  }
}
