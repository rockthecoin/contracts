use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, VerificationKey}
use cardano/assets
use cardano/transaction.{OutputReference, Transaction}
use rtc/common

pub type Datum {
  beneficiary: Address,
  policy: ByteArray,
  name: ByteArray,
  allocation: Int,
  released: Int,
  reserve_lovelace: Int,
  start_ms: Int,
  cliff_ms: Int,
  end_ms: Int,
}
pub type Action {
  Release { amount: Int, at_ms: Int, continuation: Int, payout: Int }
  Surplus { policy: ByteArray, name: ByteArray, amount: Int, continuation: Int, payout: Int }
}
pub fn valid_asset(policy: ByteArray, name: ByteArray) -> Bool {
  if policy == #"" { name == #"" } else { bytearray.length(policy) == 28 && bytearray.length(name) <= 32 }
}
pub fn vested(d: Datum, at_ms: Int) -> Int {
  if at_ms < d.cliff_ms { 0 } else if at_ms >= d.end_ms { d.allocation } else { d.allocation * (at_ms - d.start_ms) / (d.end_ms - d.start_ms) }
}
pub fn authorizes(d: Datum, action: Action, reference: OutputReference, tx: Transaction) -> Bool {
  let own = common.own_input(tx, reference).output
  let remaining = d.allocation - d.released
  let asset_quantity = assets.quantity_of(own.value, d.policy, d.name)
  let ada_principal = if d.policy == #"" { remaining } else { 0 }
  and {
    common.key_address(d.beneficiary),
    valid_asset(d.policy, d.name),
    d.allocation > 0,
    d.allocation <= common.maximum_quantity,
    d.released >= 0,
    remaining > 0,
    d.reserve_lovelace > 0,
    d.start_ms > 0,
    d.start_ms <= d.cliff_ms,
    d.cliff_ms <= d.end_ms,
    asset_quantity >= remaining + if d.policy == #"" { d.reserve_lovelace } else { 0 },
    assets.lovelace_of(own.value) >= d.reserve_lovelace + ada_principal,
    common.one_script_input(tx),
    when action is {
      Release { amount, at_ms, continuation, payout } -> {
        let paid = common.at_output(tx, payout)
        and {
          common.time_window(tx, at_ms),
          amount > 0,
          amount <= remaining,
          amount <= vested(d, at_ms) - d.released,
          paid.address == d.beneficiary,
          if amount == remaining {
            common.same_or_more(paid.value, own.value)
          } else {
            let next = common.at_output(tx, continuation)
            and {
              continuation != payout,
              next.address == own.address,
              common.datum(next) == Datum { ..d, released: d.released + amount },
              next.value == assets.add(own.value, d.policy, d.name, -amount),
              assets.quantity_of(paid.value, d.policy, d.name) >= amount,
            }
          },
        }
      }
      Surplus { policy, name, amount, continuation, payout } -> {
        expect VerificationKey(beneficiary_key) = d.beneficiary.payment_credential
        let next = common.at_output(tx, continuation)
        let paid = common.at_output(tx, payout)
        and {
          valid_asset(policy, name),
          list.has(tx.extra_signatories, beneficiary_key),
          amount > 0,
          amount <= assets.quantity_of(own.value, policy, name),
          continuation != payout,
          next.address == own.address,
          common.datum(next) == d,
          next.value == assets.add(own.value, policy, name, -amount),
          assets.quantity_of(next.value, d.policy, d.name) >= remaining + if d.policy == #"" { d.reserve_lovelace } else { 0 },
          assets.lovelace_of(next.value) >= d.reserve_lovelace + ada_principal,
          paid.address == d.beneficiary,
          assets.quantity_of(paid.value, policy, name) >= amount,
        }
      }
    },
  }
}
validator vesting {
  spend(datum: Option<Datum>, action: Action, reference: OutputReference, tx: Transaction) {
    expect Some(d) = datum
    authorizes(d, action, reference, tx)
  }
  else(_) { fail }
}
