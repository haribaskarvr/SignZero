/**
 * @description Finds Contacts to choose as signers in the Send for Signature flow: the record's own contacts, and a
 *   search across every Contact the sender can see. Runs in user mode, so sharing and field access apply. Contacts
 *   without an email address are left out, since they could not be sent a link.
 */
public with sharing class SignZeroContactPicker {
  /** @description Most contacts returned by one call. */
  private static final Integer MAX_ROWS = 200;

  /**
   * @description One Contact the sender can choose.
   */
  public class ContactOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String accountName;
  }

  /**
   * @description The contacts belonging to the record the envelope is sent from: the record itself when it is a
   *   Contact, the contacts of any Account it is or looks up to, any Contact it looks up to, and an Opportunity's
   *   contact roles. Works for custom objects through their Account and Contact lookups.
   * @param recordId the record the envelope is sent from, or null
   * @param accountId an account whose contacts are offered as well, for records that reach their account indirectly
   *   (set by the flow); or null
   * @return the contacts with an email address, by name
   */
  @AuraEnabled(cacheable=true)
  public static List<ContactOption> relatedContacts(Id recordId, Id accountId) {
    Set<Id> accountIds = new Set<Id>();
    Set<Id> contactIds = new Set<Id>();
    if (accountId != null) {
      if (accountId.getSobjectType() != Account.SObjectType) {
        throw new AuraHandledException(System.Label.SZ_Signers_Err_Contacts);
      }
      accountIds.add(accountId);
    }
    if (recordId != null) {
      collectLookups(recordId, accountIds, contactIds);
    }
    if (recordId != null && recordId.getSobjectType() == Opportunity.SObjectType) {
      for (OpportunityContactRole role : [
        SELECT ContactId
        FROM OpportunityContactRole
        WHERE OpportunityId = :recordId
        WITH USER_MODE
      ]) {
        contactIds.add(role.ContactId);
      }
    }
    if (!contactIds.isEmpty()) {
      // A contact's account brings in their colleagues too.
      for (Contact c : [SELECT AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != NULL WITH USER_MODE]) {
        accountIds.add(c.AccountId);
      }
    }
    if (accountIds.isEmpty() && contactIds.isEmpty()) {
      return new List<ContactOption>();
    }
    return options(
      [
        SELECT Id, Name, Email, Title, Account.Name
        FROM Contact
        WHERE (AccountId IN :accountIds OR Id IN :contactIds) AND Email != NULL
        WITH USER_MODE
        ORDER BY Name
        LIMIT :MAX_ROWS
      ]
    );
  }

  /**
   * @description Searches every Contact the sender can see by name or email.
   * @param term at least two characters
   * @return matching contacts with an email address, by name; empty for a shorter term
   */
  @AuraEnabled(cacheable=true)
  public static List<ContactOption> searchContacts(String term) {
    term = term == null ? '' : term.trim();
    if (term.length() < 2) {
      return new List<ContactOption>();
    }
    // The term is a bind variable; only LIKE's own wildcards need escaping.
    String pattern = '%' + term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
    return options(
      [
        SELECT Id, Name, Email, Title, Account.Name
        FROM Contact
        WHERE (Name LIKE :pattern OR Email LIKE :pattern) AND Email != NULL
        WITH USER_MODE
        ORDER BY Name
        LIMIT :MAX_ROWS
      ]
    );
  }

  /**
   * @description Adds the Account and Contact the record is or looks up to.
   * @param recordId the record
   * @param accountIds receives Account Ids
   * @param contactIds receives Contact Ids
   */
  private static void collectLookups(Id recordId, Set<Id> accountIds, Set<Id> contactIds) {
    Schema.SObjectType type = recordId.getSobjectType();
    if (type == Account.SObjectType) {
      accountIds.add(recordId);
      return;
    }
    if (type == Contact.SObjectType) {
      contactIds.add(recordId);
      return;
    }
    List<String> fields = new List<String>();
    for (Schema.SObjectField field : type.getDescribe().fields.getMap().values()) {
      Schema.DescribeFieldResult d = field.getDescribe();
      if (
        d.getType() == Schema.DisplayType.REFERENCE &&
        d.isAccessible() &&
        (d.getReferenceTo().contains(Account.SObjectType) || d.getReferenceTo().contains(Contact.SObjectType))
      ) {
        fields.add(d.getName());
      }
    }
    if (fields.isEmpty()) {
      return;
    }
    List<SObject> rows = Database.queryWithBinds(
      'SELECT ' + String.join(fields, ', ') + ' FROM ' + type + ' WHERE Id = :recordId',
      new Map<String, Object>{ 'recordId' => recordId },
      AccessLevel.USER_MODE
    );
    if (rows.isEmpty()) {
      return;
    }
    for (String field : fields) {
      Object value = rows[0].get(field);
      if (value instanceof Id) {
        Id related = (Id) value;
        if (related.getSobjectType() == Account.SObjectType) {
          accountIds.add(related);
        } else if (related.getSobjectType() == Contact.SObjectType) {
          contactIds.add(related);
        }
      }
    }
  }

  private static List<ContactOption> options(List<Contact> contacts) {
    List<ContactOption> result = new List<ContactOption>();
    for (Contact c : contacts) {
      ContactOption o = new ContactOption();
      o.id = c.Id;
      o.name = c.Name;
      o.email = c.Email;
      o.title = c.Title;
      o.accountName = c.Account?.Name;
      result.add(o);
    }
    return result;
  }
}
