use aiken/interval
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use cardano/transaction
use rtc/fixtures as f
use asset_lock
use vesting

fn datum() -> vesting.Datum {
  vesting.Datum { beneficiary: address.from_verification_key(f.owner), policy: f.policy, name: "LOCK", allocation: 1000, released: 0, reserve_lovelace: 2000000, start_ms: 100000, cliff_ms: 120000, end_ms: 200000 }
}
fn release(d: vesting.Datum, amount: Int, at_ms: Int) -> Transaction {
  let initial = Output { address: address.from_script(f.controller_hash), value: assets.from_lovelace(2000000) |> assets.add(d.policy, d.name, d.allocation - d.released), datum: InlineDatum(d), reference_script: None }
  let next = Output { ..initial, value: assets.add(initial.value, d.policy, d.name, -amount), datum: InlineDatum(vesting.Datum { ..d, released: d.released + amount }) }
  let paid = Output { address: d.beneficiary, value: assets.from_lovelace(2000000) |> assets.add(d.policy, d.name, amount), datum: NoDatum, reference_script: None }
  Transaction { ..transaction.placeholder, inputs: [Input { output_reference: f.reference, output: initial }], outputs: [next, paid], validity_range: interval.between(at_ms, at_ms + 1000) }
}
test vested_math_before_cliff() { vesting.vested(datum(), 119999) == 0 }
test vested_math_midpoint() { vesting.vested(datum(), 150000) == 500 }
test vested_math_at_end() { vesting.vested(datum(), 200000) == 1000 }
test ordinary_partial_release() { let d = datum() vesting.authorizes(d, vesting.Release { amount: 500, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, release(d, 500, 150000)) }
test partial_release_before_cliff_rejected() { let d = datum() !vesting.authorizes(d, vesting.Release { amount: 1, at_ms: 119999, continuation: 0, payout: 1 }, f.reference, release(d, 1, 119999)) }
test release_above_vested_amount_rejected() { let d = datum() !vesting.authorizes(d, vesting.Release { amount: 501, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, release(d, 501, 150000)) }
test release_cannot_claim_future_time() {
  let d = datum()
  let tx = release(d, 500, 150000)
  !vesting.authorizes(d, vesting.Release { amount: 1000, at_ms: 200000, continuation: 0, payout: 0 }, f.reference, tx)
}
test payout_cannot_go_to_another_wallet() {
  let d = datum()
  let tx = release(d, 500, 150000)
  expect [next, paid] = tx.outputs
  !vesting.authorizes(d, vesting.Release { amount: 500, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, outputs: [next, Output { ..paid, address: address.from_verification_key(f.other) }] })
}
test remaining_principal_must_stay_in_escrow() {
  let d = datum()
  let tx = release(d, 500, 150000)
  expect [next, paid] = tx.outputs
  !vesting.authorizes(d, vesting.Release { amount: 500, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, outputs: [Output { ..next, value: assets.add(next.value, d.policy, d.name, -1) }, paid] })
}
test remaining_deposit_cannot_be_withdrawn() {
  let d = datum()
  let tx = release(d, 500, 150000)
  expect [next, paid] = tx.outputs
  !vesting.authorizes(d, vesting.Release { amount: 500, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, outputs: [Output { ..next, value: assets.add(next.value, #"", #"", -1) }, paid] })
}
test two_locks_cannot_share_one_payout() {
  let d = datum()
  let tx = release(d, 500, 150000)
  expect [input] = tx.inputs
  !vesting.authorizes(d, vesting.Release { amount: 500, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, inputs: [input, Input { ..input, output_reference: transaction.OutputReference { ..f.reference, output_index: 1 } }] })
}
test full_release_returns_all_assets_and_deposit() {
  let d = datum()
  let tx = release(d, 1000, 200000)
  expect [_, paid] = tx.outputs
  vesting.authorizes(d, vesting.Release { amount: 1000, at_ms: 200000, continuation: 0, payout: 0 }, f.reference, Transaction { ..tx, outputs: [paid] })
}
test full_release_cannot_steal_donated_assets() {
  let d = datum()
  let tx = release(d, 1000, 200000)
  expect [input] = tx.inputs
  expect [_, paid] = tx.outputs
  let changed = Input { ..input, output: Output { ..input.output, value: assets.add(input.output.value, f.policy, "GIFT", 10) } }
  !vesting.authorizes(d, vesting.Release { amount: 1000, at_ms: 200000, continuation: 0, payout: 0 }, f.reference, Transaction { ..tx, inputs: [changed], outputs: [paid] })
}
fn surplus() -> Transaction {
  let d = datum()
  let tx = release(d, 100, 100000)
  expect [input] = tx.inputs
  expect [_, paid] = tx.outputs
  let funded = Output { ..input.output, value: assets.add(input.output.value, f.policy, "LOCK", 100) }
  Transaction { ..tx, inputs: [Input { ..input, output: funded }], outputs: [input.output, paid], extra_signatories: [f.owner] }
}
test beneficiary_recovers_only_surplus_before_cliff() { vesting.authorizes(datum(), vesting.Surplus { policy: f.policy, name: "LOCK", amount: 100, continuation: 0, payout: 1 }, f.reference, surplus()) }
test surplus_cannot_consume_principal() {
  let tx = surplus()
  expect [next, paid] = tx.outputs
  !vesting.authorizes(datum(), vesting.Surplus { policy: f.policy, name: "LOCK", amount: 101, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, outputs: [Output { ..next, value: assets.add(next.value, f.policy, "LOCK", -1) }, Output { ..paid, value: assets.add(paid.value, f.policy, "LOCK", 1) }] })
}
test stranger_cannot_choose_surplus_withdrawal() { let tx = surplus() !vesting.authorizes(datum(), vesting.Surplus { policy: f.policy, name: "LOCK", amount: 100, continuation: 0, payout: 1 }, f.reference, Transaction { ..tx, extra_signatories: [f.other] }) }
test ada_can_vest_without_consuming_its_storage_deposit() {
  let d = vesting.Datum { ..datum(), policy: #"", name: #"", allocation: 10000000 }
  let own = Output { address: address.from_script(f.controller_hash), value: assets.from_lovelace(12000000), datum: InlineDatum(d), reference_script: None }
  let next = Output { ..own, value: assets.from_lovelace(7000000), datum: InlineDatum(vesting.Datum { ..d, released: 5000000 }) }
  let paid = Output { address: d.beneficiary, value: assets.from_lovelace(5000000), datum: NoDatum, reference_script: None }
  let tx = Transaction { ..transaction.placeholder, inputs: [Input { output_reference: f.reference, output: own }], outputs: [next, paid], validity_range: interval.between(150000, 151000) }
  vesting.authorizes(d, vesting.Release { amount: 5000000, at_ms: 150000, continuation: 0, payout: 1 }, f.reference, tx)
}
fn locked() -> (asset_lock.Datum, Transaction) {
  let d = asset_lock.Datum { beneficiary: address.from_verification_key(f.owner), unlock_ms: 200000 }
  let own = Output { address: address.from_script(f.controller_hash), value: assets.from_lovelace(3000000) |> assets.add(f.policy, "NFT", 1) |> assets.add(f.policy, "LP", 1000), datum: InlineDatum(d), reference_script: None }
  let tx = Transaction { ..transaction.placeholder, inputs: [Input { output_reference: f.reference, output: own }], outputs: [Output { ..own, address: d.beneficiary, datum: NoDatum }], validity_range: interval.between(200000, 201000) }
  (d, tx)
}
test lock_releases_native_nft_lp_and_ada_together() { let (d, tx) = locked() asset_lock.authorizes(d, 0, f.reference, tx) }
test lock_cannot_release_early() { let (d, tx) = locked() !asset_lock.authorizes(d, 0, f.reference, Transaction { ..tx, validity_range: interval.between(199999, 201000) }) }
test lock_cannot_redirect_assets() { let (d, tx) = locked() expect [paid] = tx.outputs !asset_lock.authorizes(d, 0, f.reference, Transaction { ..tx, outputs: [Output { ..paid, address: address.from_verification_key(f.other) }] }) }
test lock_cannot_strip_one_asset() { let (d, tx) = locked() expect [paid] = tx.outputs !asset_lock.authorizes(d, 0, f.reference, Transaction { ..tx, outputs: [Output { ..paid, value: assets.add(paid.value, f.policy, "NFT", -1) }] }) }
test lock_cannot_use_empty_validity_range() { let (d, tx) = locked() !asset_lock.authorizes(d, 0, f.reference, Transaction { ..tx, validity_range: interval.between(500000, 200000) }) }
