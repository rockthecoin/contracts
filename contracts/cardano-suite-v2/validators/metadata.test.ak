use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use cardano/transaction
use rtc/common
use rtc/fixtures as f
use rtc/issuance.{Datum, MetadataDatum, MetadataState, State}
use metadata

fn context() -> (MetadataDatum, Transaction) {
  let control = f.datum(1)
  let d = MetadataDatum { metadata: f.metadata(), version: 3, state: MetadataState { policy: f.policy, reference_name: common.nft_name(common.reference_label, 1), controller_name: common.collection_marker, controller_hash: f.controller_hash, frozen: False } }
  let own = Output { address: address.from_script(f.metadata_hash), value: assets.from_lovelace(3000000) |> assets.add(f.policy, d.state.reference_name, 1), datum: InlineDatum(d), reference_script: None }
  let next = MetadataDatum { ..d, state: MetadataState { ..d.state, frozen: True } }
  let tx = Transaction { ..transaction.placeholder, inputs: [Input { output_reference: f.reference, output: own }], reference_inputs: [Input { output_reference: transaction.OutputReference { ..f.reference, output_index: 1 }, output: f.state_output(control) }], outputs: [Output { ..own, datum: InlineDatum(next) }], extra_signatories: [f.owner] }
  (d, tx)
}
test creator_can_freeze_an_item() { let (d, tx) = context() metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, tx) }
test creator_cannot_unfreeze_a_frozen_item() { let (d, tx) = context() !metadata.authorizes(MetadataDatum { ..d, state: MetadataState { ..d.state, frozen: True } }, metadata.Update { metadata: d.metadata, freeze: False }, f.reference, tx) }
test metadata_requires_current_collection_owner() { let (d, tx) = context() !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, extra_signatories: [f.other] }) }
test metadata_cannot_use_fake_controller() {
  let (d, tx) = context()
  expect [input] = tx.reference_inputs
  let bad = Input { ..input, output: Output { ..input.output, address: address.from_verification_key(f.other) } }
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, reference_inputs: [bad] })
}
test metadata_cannot_release_reference_nft() {
  let (d, tx) = context()
  expect [output] = tx.outputs
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, outputs: [Output { ..output, address: address.from_verification_key(f.owner) }] })
}
test metadata_cannot_remove_deposit() {
  let (d, tx) = context()
  expect [output] = tx.outputs
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, outputs: [Output { ..output, value: assets.add(output.value, #"", #"", -1) }] })
}
test global_metadata_freeze_applies_to_existing_items() {
  let (d, tx) = context()
  expect [input] = tx.reference_inputs
  let control = f.datum(1)
  let changed = Datum { ..control, state: State { ..control.state, metadata_mutable: False } }
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, reference_inputs: [Input { ..input, output: f.state_output(changed) }] })
}
test owner_transfer_changes_existing_item_authority() {
  let (d, tx) = context()
  expect [input] = tx.reference_inputs
  let control = f.datum(1)
  let changed = Datum { ..control, state: State { ..control.state, owner: Some(f.other) } }
  let tx = Transaction { ..tx, reference_inputs: [Input { ..input, output: f.state_output(changed) }], extra_signatories: [f.other] }
  metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, tx)
}
test metadata_cannot_burn_reference() {
  let (d, tx) = context()
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, mint: assets.from_asset(f.policy, d.state.reference_name, -1) })
}
test metadata_cannot_add_foreign_assets_to_reference_output() {
  let (d, tx) = context()
  expect [output] = tx.outputs
  !metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, outputs: [Output { ..output, value: assets.add(output.value, f.other, "DUST", 1) }] })
}
test metadata_accepts_an_ada_deposit_topup() {
  let (d, tx) = context()
  expect [output] = tx.outputs
  metadata.authorizes(d, metadata.Update { metadata: d.metadata, freeze: True }, f.reference, Transaction { ..tx, outputs: [Output { ..output, value: assets.add(output.value, #"", #"", 1) }] })
}
