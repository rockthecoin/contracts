use aiken/interval
use cardano/address.{Address}
use cardano/transaction.{OutputReference, Transaction}
use rtc/common

pub type Datum { beneficiary: Address, unlock_ms: Int }
pub fn authorizes(d: Datum, payout: Int, reference: OutputReference, tx: Transaction) -> Bool {
  let own = common.own_input(tx, reference).output
  let paid = common.at_output(tx, payout)
  and {
    common.key_address(d.beneficiary),
    d.unlock_ms > 0,
    !interval.is_empty(tx.validity_range),
    interval.is_entirely_after(tx.validity_range, d.unlock_ms - 1),
    common.one_script_input(tx),
    paid.address == d.beneficiary,
    common.same_or_more(paid.value, own.value),
  }
}
validator asset_lock {
  spend(datum: Option<Datum>, payout: Int, reference: OutputReference, tx: Transaction) {
    expect Some(d) = datum
    authorizes(d, payout, reference, tx)
  }
  else(_) { fail }
}
