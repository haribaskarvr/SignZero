/**
 * @description "Resend Invitation" quick action, on an envelope (everyone whose turn it is) or a single signer. Sends a
 *   fresh link through SignZeroInvitationService, which logs it in the audit trail.
 */
public with sharing class SignZeroResendController {
  /**
   * @description A signer who will be emailed, for the confirmation screen.
   */
  public class Target {
    /** @description Signer's name. */
    @AuraEnabled
    public String name;
    /** @description Signer's email address. */
    @AuraEnabled
    public String email;
  }

  /**
   * @description Lists who would be re-invited, for the confirmation screen. Throws a readable reason if nobody can be.
   * @param recordId a Signature Request (everyone whose turn it is) or a Signature Recipient
   * @return the signers who would get a new link
   */
  @AuraEnabled
  public static List<Target> previewResend(Id recordId) {
    List<Target> targets = new List<Target>();
    for (SignZero_Recipient__c r : resolveTargets(recordId)) {
      Target t = new Target();
      t.name = r.Name;
      t.email = r.Email__c;
      targets.add(t);
    }
    return targets;
  }

  /**
   * @description Emails new signing links; links sent before stop working.
   * @param recordId a Signature Request (everyone whose turn it is) or a Signature Recipient
   * @return how many signers were emailed
   */
  @AuraEnabled
  public static Integer resend(Id recordId) {
    List<SignZero_Recipient__c> targets = resolveTargets(recordId);
    Set<Id> ids = new Map<Id, SignZero_Recipient__c>(targets).keySet();
    try {
      SignZeroInvitationService.send(ids, 're-sent by ' + UserInfo.getName());
      update as system new SignZero_Request__c(
        Id = targets[0].SignZero_Request__c,
        Error_Message__c = null
      );
    } catch (Exception e) {
      throw fail(
        String.format(
          System.Label.SZ_Resend_Err_Send_Failed,
          new List<Object>{ e.getMessage() }
        )
      );
    }
    return targets.size();
  }

  /**
   * @description Finds the signers to re-invite. The user must be able to see the record.
   * @param recordId a Signature Request or a Signature Recipient
   * @return the signers whose turn it is; throws a readable reason when there are none
   */
  private static List<SignZero_Recipient__c> resolveTargets(Id recordId) {
    Id requestId;
    Id onlyRecipientId;
    if (recordId.getSobjectType() == SignZero_Recipient__c.SObjectType) {
      List<SignZero_Recipient__c> rows = [
        SELECT SignZero_Request__c
        FROM SignZero_Recipient__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
      if (rows.isEmpty()) {
        throw fail(System.Label.SZ_Resend_Err_Signer_Not_Found);
      }
      requestId = rows[0].SignZero_Request__c;
      onlyRecipientId = recordId;
    } else {
      requestId = recordId;
    }
    List<SignZero_Request__c> envelopes = [
      SELECT
        Id,
        Status__c,
        (
          SELECT
            Id,
            Name,
            Email__c,
            Status__c,
            Routing_Order__c,
            SignZero_Request__c
          FROM Recipients__r
          ORDER BY Routing_Order__c
        )
      FROM SignZero_Request__c
      WHERE Id = :requestId
      WITH USER_MODE
    ];
    if (envelopes.isEmpty()) {
      throw fail(System.Label.SZ_Resend_Err_Not_Found);
    }
    if (envelopes[0].Status__c != SignZeroConstants.ENVELOPE_OUT_FOR_SIGNATURE) {
      throw fail(
        String.format(
          System.Label.SZ_Resend_Err_Status,
          new List<Object>{ envelopes[0].Status__c }
        )
      );
    }

    // Whose turn it is: the lowest routing order with anyone still to sign.
    Decimal activeOrder = null;
    List<SignZero_Recipient__c> due = new List<SignZero_Recipient__c>();
    for (SignZero_Recipient__c r : envelopes[0].Recipients__r) {
      if (!SignZeroConstants.SIGNER_AWAITING.contains(r.Status__c)) {
        continue;
      }
      if (activeOrder == null) {
        activeOrder = r.Routing_Order__c;
      }
      if (r.Routing_Order__c == activeOrder) {
        due.add(r);
      }
    }
    if (onlyRecipientId == null) {
      if (due.isEmpty()) {
        throw fail(System.Label.SZ_Resend_Err_Nobody_Waiting);
      }
      return due;
    }
    for (SignZero_Recipient__c r : due) {
      if (r.Id == onlyRecipientId) {
        return new List<SignZero_Recipient__c>{ r };
      }
    }
    throw fail(System.Label.SZ_Resend_Err_Not_Due);
  }

  /**
   * @description Builds an error the quick action shows as is.
   * @param message the message for the sender
   * @return the exception to throw
   */
  private static AuraHandledException fail(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
