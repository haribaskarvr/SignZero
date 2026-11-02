/**
 * @description Moves envelopes forward after a signer acts: invites the next routing order, seals completed envelopes
 *   and keeps the sender informed. Queued from SignZeroEventTrigger so the work runs outside the site guest user's
 *   context.
 */
public without sharing class SignZeroProgressionJob implements Queueable {
  private final Set<Id> requestIds;
  private final Set<Id> declinedIds;
  private final Set<Id> signedRecipientIds;
  private Set<Id> reassignedToIds = new Set<Id>();

  /**
   * @description Creates a job without signature notifications.
   * @param requestIds envelopes where someone signed or reassigned
   * @param declinedIds envelopes where someone declined
   */
  public SignZeroProgressionJob(Set<Id> requestIds, Set<Id> declinedIds) {
    this(requestIds, declinedIds, new Set<Id>());
  }

  /**
   * @description Creates a job that also tells the sender who signed.
   * @param requestIds envelopes where someone signed or reassigned
   * @param declinedIds envelopes where someone declined
   * @param signedRecipientIds signers who just signed, for the sender's notifications
   */
  public SignZeroProgressionJob(
    Set<Id> requestIds,
    Set<Id> declinedIds,
    Set<Id> signedRecipientIds
  ) {
    this.requestIds = requestIds;
    this.declinedIds = declinedIds;
    this.signedRecipientIds = signedRecipientIds;
  }

  /**
   * @description Queues one job for a batch of SignZero_Event__e events.
   * @param events the events from SignZeroEventTrigger
   */
  public static void handleEvents(List<SignZero_Event__e> events) {
    Set<Id> requestIds = new Set<Id>();
    Set<Id> declinedIds = new Set<Id>();
    Set<Id> signedRecipientIds = new Set<Id>();
    Set<Id> reassignedToIds = new Set<Id>();
    for (SignZero_Event__e evt : events) {
      Id requestId = Id.valueOf(evt.SignZero_Request_Id__c);
      if (evt.Action__c == SignZeroConstants.ACTION_DECLINED) {
        declinedIds.add(requestId);
      } else if (evt.Action__c == SignZeroConstants.ACTION_REASSIGNED) {
        requestIds.add(requestId);
        reassignedToIds.add(Id.valueOf(evt.Recipient_Id__c));
      } else {
        requestIds.add(requestId);
        if (String.isNotBlank(evt.Recipient_Id__c)) {
          signedRecipientIds.add(Id.valueOf(evt.Recipient_Id__c));
        }
      }
    }
    SignZeroProgressionJob job = new SignZeroProgressionJob(
      requestIds,
      declinedIds,
      signedRecipientIds
    );
    job.reassignedToIds = reassignedToIds;
    System.enqueueJob(job);
  }

  /**
   * @description Invites the next signers, seals finished envelopes and notifies the senders.
   * @param ctx the queueable context (unused; tests pass null)
   */
  public void execute(QueueableContext ctx) {
    SignZeroRecordGuard.markProcessUpdate();
    List<Id> toSeal = new List<Id>();
    Set<Id> toInvite = new Set<Id>();
    for (SignZero_Request__c req : [
      SELECT
        Id,
        Status__c,
        (
          SELECT Id, Status__c, Routing_Order__c
          FROM Recipients__r
          ORDER BY Routing_Order__c
        )
      FROM SignZero_Request__c
      WHERE Id IN :requestIds AND Status__c = :SignZeroConstants.ENVELOPE_OUT_FOR_SIGNATURE
      WITH SYSTEM_MODE
    ]) {
      // Invite anyone in the lowest unsigned routing order who has not been sent yet.
      Decimal nextOrder = null;
      for (SignZero_Recipient__c r : req.Recipients__r) {
        if (!SignZeroConstants.SIGNER_AWAITING.contains(r.Status__c)) {
          continue; // signed, or handed to someone else
        }
        if (nextOrder == null) {
          nextOrder = r.Routing_Order__c;
        }
        if (r.Routing_Order__c == nextOrder && r.Status__c == SignZeroConstants.SIGNER_PENDING) {
          toInvite.add(r.Id);
        }
      }
      if (nextOrder == null) {
        toSeal.add(req.Id);
      }
    }

    if (!toSeal.isEmpty()) {
      SignZeroSealService.sealAndFinalize(toSeal);
    }
    inviteNextSigners(toInvite);
    notifySignatures(new Set<Id>(toSeal));
    notifyReassignments();

    if (!declinedIds.isEmpty()) {
      for (SignZero_Request__c req : [
        SELECT
          Id,
          Name,
          OwnerId,
          Document_Name__c,
          (
            SELECT Name, Decline_Reason__c
            FROM Recipients__r
            WHERE Status__c = :SignZeroConstants.SIGNER_DECLINED
            LIMIT 1
          )
        FROM SignZero_Request__c
        WHERE Id IN :declinedIds
        WITH SYSTEM_MODE
      ]) {
        String who = req.Recipients__r.isEmpty()
          ? System.Label.SZ_Owner_A_Signer
          : req.Recipients__r[0].Name;
        String why = req.Recipients__r.isEmpty()
          ? null
          : req.Recipients__r[0].Decline_Reason__c;
        SignZeroNotifier.notifyOwner(
          req,
          System.Label.SZ_Outcome_Declined,
          SignZeroNotifier.fill(
            System.Label.SZ_Owner_Declined,
            new List<Object>{ who }
          ) +
            (String.isBlank(why)
              ? ''
              : '\n' +
                SignZeroNotifier.fill(
                  System.Label.SZ_Mail_Reason,
                  new List<Object>{ why }
                ))
        );
      }
    }
  }

  /**
   * @description Invites the next routing order. If the email cannot be sent (for example, the daily limit is used up),
   *   the invitation is rolled back, the error is recorded on the envelope and the sender is told.
   * @param recipientIds signers to invite
   */
  private void inviteNextSigners(Set<Id> recipientIds) {
    if (recipientIds.isEmpty()) {
      return;
    }
    Savepoint beforeInvites = Database.setSavepoint();
    try {
      SignZeroInvitationService.send(recipientIds);
    } catch (Exception e) {
      Database.rollback(beforeInvites);
      Set<Id> envelopeIds = new Set<Id>();
      for (SignZero_Recipient__c r : [
        SELECT SignZero_Request__c
        FROM SignZero_Recipient__c
        WHERE Id IN :recipientIds
        WITH SYSTEM_MODE
      ]) {
        envelopeIds.add(r.SignZero_Request__c);
      }
      List<SignZero_Request__c> envelopes = [
        SELECT Id, Name, OwnerId, Document_Name__c
        FROM SignZero_Request__c
        WHERE Id IN :envelopeIds
        WITH SYSTEM_MODE
      ];
      for (SignZero_Request__c env : envelopes) {
        env.Error_Message__c = String.format(
          System.Label.SZ_Err_Invite_Failed,
          new List<Object>{ e.getMessage() }
        );
      }
      update as system envelopes;
      for (SignZero_Request__c env : envelopes) {
        SignZeroNotifier.bell(
          env,
          SignZeroNotifier.bellTitle(env, System.Label.SZ_Bell_Invite_Failed),
          SignZeroNotifier.bellBody(env, env.Error_Message__c)
        );
      }
    }
  }

  /**
   * @description Tells each sender who delegated their signature, e.g. "Casey Customer reassigned to Dana Delegate".
   */
  private void notifyReassignments() {
    if (reassignedToIds.isEmpty()) {
      return;
    }
    for (SignZero_Recipient__c original : [
      SELECT
        Name,
        Reassign_Reason__c,
        Reassigned_To__r.Name,
        Reassigned_To__r.Email__c,
        SignZero_Request__r.Name,
        SignZero_Request__r.OwnerId,
        SignZero_Request__r.Document_Name__c
      FROM SignZero_Recipient__c
      WHERE Reassigned_To__c IN :reassignedToIds
      WITH SYSTEM_MODE
    ]) {
      SignZero_Request__c req = original.SignZero_Request__r;
      SignZeroNotifier.bell(
        req,
        SignZeroNotifier.bellTitle(
          req,
          SignZeroNotifier.fill(
            System.Label.SZ_Bell_Reassigned,
            new List<Object>{ original.Name, original.Reassigned_To__r.Name }
          )
        ),
        SignZeroNotifier.bellBody(
          req,
          original.Reassigned_To__r.Email__c +
            (String.isBlank(original.Reassign_Reason__c)
              ? ''
              : '. ' +
                SignZeroNotifier.fill(
                  System.Label.SZ_Mail_Reason,
                  new List<Object>{ original.Reassign_Reason__c }
                ))
        )
      );
    }
  }

  /**
   * @description Tells each sender who signed, e.g. "Casey Customer signed (1 of 2)".
   * @param completedIds envelopes that just completed, which get the Completed notice instead
   */
  private void notifySignatures(Set<Id> completedIds) {
    if (signedRecipientIds.isEmpty()) {
      return;
    }
    for (SignZero_Recipient__c r : [
      SELECT
        Name,
        SignZero_Request__c,
        SignZero_Request__r.Name,
        SignZero_Request__r.OwnerId,
        SignZero_Request__r.Document_Name__c,
        SignZero_Request__r.Signers_Signed__c,
        SignZero_Request__r.Signers_Total__c
      FROM SignZero_Recipient__c
      WHERE Id IN :signedRecipientIds AND Status__c = :SignZeroConstants.SIGNER_SIGNED
      WITH SYSTEM_MODE
    ]) {
      if (completedIds.contains(r.SignZero_Request__c)) {
        continue;
      }
      SignZero_Request__c req = r.SignZero_Request__r;
      SignZeroNotifier.bell(
        req,
        SignZeroNotifier.bellTitle(
          req,
          SignZeroNotifier.fill(
            System.Label.SZ_Bell_Signed,
            new List<Object>{ r.Name }
          )
        ),
        SignZeroNotifier.bellBody(
          req,
          SignZeroNotifier.fill(
            System.Label.SZ_Bell_Signed_Progress,
            new List<Object>{
              req.Signers_Signed__c.intValue(),
              req.Signers_Total__c.intValue()
            }
          )
        )
      );
    }
  }
}
