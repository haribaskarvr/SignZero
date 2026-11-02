/**
 * @description Finds email setup problems that silently stop SignZero's emails: Salesforce accepts mail from an
 *   unverified sender and drops it later, so neither Apex nor the sender sees an error. Used by the Send for Signature
 *   flow and SignZero Home.
 */
public with sharing class SignZeroEmailCheck {
  /**
   * @description One email setup problem.
   */
  public class Issue {
    /** @description "error" when emails will not arrive, "warning" when some may not. */
    @AuraEnabled
    public String severity;
    /** @description What is wrong and how to fix it. */
    @AuraEnabled
    public String message;

    Issue(String severity, String message) {
      this.severity = severity;
      this.message = message;
    }
  }

  /**
   * @description Flow action result: whether to show the email warning screen.
   */
  public class FlowResult {
    /** @description True when invitations sent now will not be delivered. */
    @InvocableVariable(
      label='Has Errors'
      description='True when invitations sent now will not be delivered.'
    )
    public Boolean hasErrors;
    /** @description True when anything was found, including warnings. */
    @InvocableVariable(
      label='Has Issues'
      description='True when anything was found, including warnings.'
    )
    public Boolean hasIssues;
  }

  /**
   * @description Checks the current user's email setup.
   * @return the problems found, errors first; empty when everything looks right
   */
  @AuraEnabled
  public static List<Issue> check() {
    Boolean canSend = true;
    try {
      // Throws when deliverability is not "All email" or the daily limit is used up.
      Messaging.reserveSingleEmailCapacity(1);
    } catch (Exception e) {
      canSend = false;
    }
    String address = SignZeroSettings.orgWideEmailAddress();
    Boolean addressFound = false;
    Boolean addressVerified = false;
    User me;
    if (String.isNotBlank(address)) {
      for (OrgWideEmailAddress row : [
        SELECT IsVerified
        FROM OrgWideEmailAddress
        WHERE Address = :address
        WITH SYSTEM_MODE
        LIMIT 1
      ]) {
        addressFound = true;
        addressVerified = row.IsVerified;
      }
    } else {
      me = [
        SELECT Email, HasUserVerifiedEmail
        FROM User
        WHERE Id = :UserInfo.getUserId()
        WITH SYSTEM_MODE
      ];
    }
    return evaluate(canSend, address, addressFound, addressVerified, me);
  }

  /**
   * @description Turns the facts found into issues, errors first. Separate from the queries so every case can be
   *   tested.
   * @param canSend whether Salesforce will send email now
   * @param address the org-wide address in SignZero Branding, or blank
   * @param addressFound whether that address exists
   * @param addressVerified whether it is verified
   * @param me the current user (Email, HasUserVerifiedEmail); only used when no org-wide address is set
   * @return the issues, errors first
   */
  @TestVisible
  private static List<Issue> evaluate(
    Boolean canSend,
    String address,
    Boolean addressFound,
    Boolean addressVerified,
    User me
  ) {
    List<Issue> issues = new List<Issue>();
    if (!canSend) {
      issues.add(new Issue(SignZeroConstants.SEVERITY_ERROR, System.Label.SZ_Email_Check_Deliverability));
    }
    if (String.isNotBlank(address)) {
      if (!addressFound) {
        issues.add(error(System.Label.SZ_Email_Check_Owea_Missing, address));
      } else if (!addressVerified) {
        issues.add(error(System.Label.SZ_Email_Check_Owea_Unverified, address));
      }
      return issues;
    }
    // Without an org-wide address, emails come from the sender, whose address must be verified.
    if (me != null && !me.HasUserVerifiedEmail) {
      issues.add(error(System.Label.SZ_Email_Check_User_Unverified, me.Email));
    }
    issues.add(new Issue(SignZeroConstants.SEVERITY_WARNING, System.Label.SZ_Email_Check_No_Owea));
    return issues;
  }

  /**
   * @description Builds an error issue from a label.
   * @param label the label, with a {0} placeholder
   * @param value the value for {0}
   * @return the issue
   */
  private static Issue error(String label, String value) {
    return new Issue(
      SignZeroConstants.SEVERITY_ERROR,
      String.format(label, new List<Object>{ value })
    );
  }

  /**
   * @description Flow action: checks the email setup so the flow can warn the sender before anything is sent.
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
      result.hasErrors = result.hasErrors || issue.severity == SignZeroConstants.SEVERITY_ERROR;
    }
    return new List<FlowResult>{ result };
  }
}
