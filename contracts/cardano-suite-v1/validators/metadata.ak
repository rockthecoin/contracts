use aiken/collection/list
use cardano/transaction.{OutputReference, Transaction}
use cardano/assets
use rtc/common
use rtc/issuance.{Datum, MetadataDatum}
use rtc/issuance

pub type Update { metadata: Data, freeze: Bool }
pub fn authorizes(d: MetadataDatum, change: Update, reference: OutputReference, tx: Transaction) -> Bool {
  let own = common.own_input(tx, reference).output
  let s = d.state
  expect [controller] = list.filter(tx.reference_inputs, fn(input) {
    assets.quantity_of(input.output.value, s.policy, s.controller_name) == 1
  })
  expect control: Datum = common.datum(controller.output)
  expect [next_output] = list.filter(tx.outputs, fn(o) { assets.quantity_of(o.value, s.policy, s.reference_name) == 1 })
  let next = MetadataDatum { metadata: change.metadata, version: 3, state: issuance.MetadataState { ..s, frozen: change.freeze } }
  and {
    d.version == 3,
    !s.frozen,
    common.script_address(controller.output.address, s.controller_hash),
    issuance.valid_state(control),
    control.state.policy == s.policy,
    control.state.rules.kind == 1,
    control.state.rules.state_name == s.controller_name,
    common.script_address(own.address, control.state.rules.metadata_script),
    control.state.metadata_mutable,
    common.signed(control.state.owner, tx),
    assets.quantity_of(own.value, s.policy, s.reference_name) == 1,
    assets.quantity_of(tx.mint, s.policy, s.reference_name) == 0,
    next_output.address == own.address,
    common.same_or_more(next_output.value, own.value),
    common.metadata_valid(change.metadata),
    common.datum(next_output) == next,
  }
}
validator metadata {
  spend(datum: Option<MetadataDatum>, change: Update, own_reference: OutputReference, tx: Transaction) {
    expect Some(d) = datum
    authorizes(d, change, own_reference, tx)
  }
  else(_) { fail }
}
