use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use rtc/issuance.{Action, Configuration, Datum}
use rtc/issuance

validator policy(configuration: Configuration) {
  mint(_redeemer: Data, policy: PolicyId, tx: Transaction) {
    issuance.policy_authorizes(configuration, policy, tx)
  }
  else(_) { fail }
}
validator controller {
  spend(datum: Option<Datum>, action: Action, own_reference: OutputReference, tx: Transaction) {
    expect Some(d) = datum
    issuance.controller_authorizes(d, action, own_reference, tx)
  }
  else(_) { fail }
}
