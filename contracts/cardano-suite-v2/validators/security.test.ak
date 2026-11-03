use aiken/collection/list
use aiken/primitive/bytearray
use cardano/assets
use cardano/transaction.{Input, Output, Transaction}
use rtc/common
use rtc/fixtures as f
use rtc/issuance.{Burn, Datum, State}
use rtc/issuance

fn basket(count: Int) -> assets.Assets {
  assets.from_lovelace(20000000)
    |> assets.merge(assets.from_asset_list([Pair(f.other, list.map(list.range(1, count), fn(i) { Pair(bytearray.from_int_big_endian(i, 2), i) }))]))
}
fn naive_cover(value: assets.Assets, required: assets.Assets) -> Bool {
  list.all(assets.flatten(required), fn(entry) {
    let (policy, name, quantity) = entry
    assets.quantity_of(value, policy, name) >= quantity
  })
}
test linear_comparison_matches_reference_for_complete_values() {
  list.all(list.range(1, 20), fn(count) {
    let required = basket(count)
    let equal = common.same_or_more(required, required)
    let extra = assets.add(required, f.owner, "EXTRA", 42)
    let short = assets.add(required, f.other, bytearray.from_int_big_endian(count, 2), -1)
    let larger = assets.add(required, f.other, bytearray.from_int_big_endian(count, 2), 1)
    and {
      equal,
      common.same_or_more(extra, required),
      common.same_or_more(larger, required),
      !common.same_or_more(short, required),
      common.same_or_more(short, required) == naive_cover(short, required),
      common.same_or_more(extra, required) == naive_cover(extra, required),
    }
  })
}
test linear_comparison_handles_missing_and_extra_policies() {
  let required = basket(3)
  and {
    common.same_or_more(required, assets.zero),
    !common.same_or_more(assets.zero, required),
    !common.same_or_more(assets.from_lovelace(20000000), required),
    !common.same_or_more(assets.add(required, #"", #"", -1), required),
    common.same_or_more(assets.add(required, #"", #"", 1), required),
  }
}
fn burned() -> (Datum, Transaction) {
  let old = f.datum(0)
  let next = Datum { ..old, state: State { ..old.state, outstanding: 99 } }
  (old, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", -1), [], []))
}
test holder_burn_cannot_add_foreign_assets_to_controller() {
  let (old, tx) = burned()
  expect [out] = tx.outputs
  !issuance.controller_authorizes(old, Burn, f.reference, Transaction { ..tx, outputs: [Output { ..out, value: assets.add(out.value, f.other, "DUST", 1) }] })
}
test holder_burn_cannot_lock_user_tokens_in_controller() {
  let (old, tx) = burned()
  expect [out] = tx.outputs
  !issuance.controller_authorizes(old, Burn, f.reference, Transaction { ..tx, outputs: [Output { ..out, value: assets.add(out.value, f.policy, #"0014df10525443", 1) }] })
}
test holder_burn_can_preserve_or_increase_ada_deposit() {
  let (old, tx) = burned()
  expect [out] = tx.outputs
  issuance.controller_authorizes(old, Burn, f.reference, tx) && issuance.controller_authorizes(old, Burn, f.reference, Transaction { ..tx, outputs: [Output { ..out, value: assets.add(out.value, #"", #"", 1) }] })
}
test controller_rejects_contaminated_initial_input() {
  let (old, tx) = burned()
  expect [input] = tx.inputs
  expect [out] = tx.outputs
  let contaminated = assets.add(input.output.value, f.other, "DUST", 1)
  !issuance.controller_authorizes(old, Burn, f.reference, Transaction { ..tx, inputs: [Input { ..input, output: Output { ..input.output, value: contaminated } }], outputs: [Output { ..out, value: contaminated }] })
}
test reference_value_allows_only_unique_reference_and_ada() {
  let marker = f.datum(0).state.rules.state_name
  let value = assets.from_lovelace(3000000) |> assets.add(f.policy, marker, 1)
  and {
    common.reference_value(value, f.policy, marker),
    !common.reference_value(assets.add(value, f.other, "DUST", 1), f.policy, marker),
    !common.reference_value(assets.add(value, f.policy, marker, 1), f.policy, marker),
    !common.reference_value(assets.from_lovelace(3000000), f.policy, marker),
  }
}
