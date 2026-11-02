/**
 * @description Apex-defined type for one signer, so Flow can pass extra signers to the "Dispatch Document via SignZero"
 *   action.
 */
public inherited sharing class SignZeroSigner {
  /** @description Signer's full name. */
  @AuraEnabled
  public String name;
  /** @description Address the signing link is sent to. */
  @AuraEnabled
  public String email;
  /** @description A Signer Role value; blank means Customer. */
  @AuraEnabled
  public String role;
  /** @description When they sign; signers with the same order sign in parallel. */
  @AuraEnabled
  public Integer routingOrder;

  /**
   * @description Creates an empty signer, for Flow to fill in.
   */
  public SignZeroSigner() {
  }

  /**
   * @description Creates a signer in Apex.
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
