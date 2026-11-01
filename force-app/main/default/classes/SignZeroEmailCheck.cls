/**
 * Finds email setup problems that stop SignZero's emails from being delivered. Salesforce accepts an email from
 * an unverified sender and drops it later, so neither Apex nor the sender ever sees an error; this check looks for
 * the usual causes up front. Used by the "Send for Signature" flow and the SignZero Home page.
 */
public with sharing class SignZeroEmailCheck {
  public static final String ERROR = 'error';
  public static final String WARNING = 'warning';

  /** One problem found. */
  public class Issue {
    /** "error" when emails will not arrive, "warning" when some may not. */
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public String message;

    Issue(String severity, String message) {
      this.severity = severity;
      this.message = message;
    }
  }

  /** For the flow: whether to stop and show the email warning screen. */
  public class FlowResult {
    @InvocableVariable(
      label='Has Errors'
      description='True when invitations sent now will not be delivered.'
    )
    public Boolean hasErrors;
    @InvocableVariable(
      label='Has Issues'
      description='True when anything was found, including warnings.'
    )
    public Boolean hasIssues;
  }

  /**
   * Checks the email setup for the current user.
   * @return the problems found, errors first; empty when everything looks right
   */
  @AuraEnabled
  public static List<Issue> check() {
    List<Issue> errors = new List<Issue>();
    List<Issue> warnings = new List<Issue>();
    try {
      // Throws when email deliverability is not "All email" or the daily limit is used up.
      Messaging.reserveSingleEmailCapacity(1);
    } catch (Exception e) {
      errors.add(new Issue(ERROR, System.Label.SZ_Email_Check_Deliverability));
    }

    String address = SignZeroSettings.get().Org_Wide_Email_Address__c;
    if (String.isNotBlank(address)) {
      List<OrgWideEmailAddress> rows = [
        SELECT IsVerified
        FROM OrgWideEmailAddress
        WHERE Address = :address
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        errors.add(
          new Issue(
            ERROR,
            String.format(
              System.Label.SZ_Email_Check_Owea_Missing,
              new List<Object>{ address }
            )
          )
        );
      } else if (!rows[0].IsVerified) {
        errors.add(
          new Issue(
            ERROR,
            String.format(
              System.Label.SZ_Email_Check_Owea_Unverified,
              new List<Object>{ address }
            )
          )
        );
      }
    } else {
      // Without an org-wide address, invitations come from the sender's own address, which must be verified.
      User me = [
        SELECT Email, HasUserVerifiedEmail
        FROM User
        WHERE Id = :UserInfo.getUserId()
        WITH SYSTEM_MODE
      ];
      if (!me.HasUserVerifiedEmail) {
        errors.add(
          new Issue(
            ERROR,
            String.format(
              System.Label.SZ_Email_Check_User_Unverified,
              new List<Object>{ me.Email }
            )
          )
        );
      }
      warnings.add(new Issue(WARNING, System.Label.SZ_Email_Check_No_Owea));
    }
    errors.addAll(warnings);
    return errors;
  }

  /**
   * Flow action: checks the email setup so the flow can warn the sender before anything is sent.
   * @return one result
   */
  @InvocableMethod(
    label='Check SignZero Email Setup'
    description='Finds email setup problems that would stop SignZero emails from being delivered.'
    category='SignZero'
  )
  public static List<FlowResult> checkForFlow() {
    FlowResult result = new FlowResult();
    result.hasErrors = false;
    result.hasIssues = false;
    for (Issue issue : check()) {
      result.hasIssues = true;
      result.hasErrors = result.hasErrors || issue.severity == ERROR;
    }
    return new List<FlowResult>{ result };
  }
}
