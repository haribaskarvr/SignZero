/**
 * Apex-defined type so Flow can pass extra signers to the "Dispatch Document via SignZero" action.
 */
public inherited sharing class SignZeroSigner {
  @AuraEnabled
  public String name;
  @AuraEnabled
  public String email;
  @AuraEnabled
  public String role;
  @AuraEnabled
  public Integer routingOrder;

  /** Empty signer, filled in by Flow. */
  public SignZeroSigner() {
  }

  /**
   * A signer built in Apex.
   * @param name signer's full name
   * @param email address the signing link is sent to
   * @param role a Signer Role value; blank means Customer
   * @param routingOrder when they sign; signers with the same order sign in parallel
   */
  public SignZeroSigner(
    String name,
    String email,
    String role,
    Integer routingOrder
  ) {
    this.name = name;
    this.email = email;
    this.role = role;
    this.routingOrder = routingOrder;
  }
}
