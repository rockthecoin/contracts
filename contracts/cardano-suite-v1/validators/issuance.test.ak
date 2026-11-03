use aiken/builtin
use aiken/interval
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use cardano/transaction
use rtc/common
use rtc/fixtures as f
use rtc/issuance.{AcceptOwnership, BeginOwnership, Burn, CloseMinting, Configuration, Datum, Issue, MetadataDatum, MetadataState, NftItem, Renounce, Rules, SetMinters, SetPause, State, UpdateMetadata}
use rtc/issuance

fn issue_tx() -> Transaction {
  let old = f.datum(0)
  let next = Datum { ..old, state: State { ..old.state, issued: 150, outstanding: 150 } }
  f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 50), [f.owner], [])
}
test owner_mints_capped_native_tokens() { issuance.controller_authorizes(f.datum(0), Issue { items: [] }, f.reference, issue_tx()) }
test unauthorized_minter() { let tx = issue_tx() !issuance.controller_authorizes(f.datum(0), Issue { items: [] }, f.reference, Transaction { ..tx, extra_signatories: [f.other] }) }
test delegated_minter_can_issue() {
  let old = f.datum(0)
  let old = Datum { ..old, state: State { ..old.state, minters: [f.other] } }
  let next = Datum { ..old, state: State { ..old.state, issued: 150, outstanding: 150 } }
  issuance.controller_authorizes(old, Issue { items: [] }, f.reference, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 50), [f.other], []))
}
test cap_cannot_increase() {
  let old = f.datum(0)
  let next = Datum { ..old, state: State { ..old.state, rules: Rules { ..old.state.rules, maximum_supply: 2000 }, issued: 150, outstanding: 150 } }
  !issuance.controller_authorizes(old, Issue { items: [] }, f.reference, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 50), [f.owner], []))
}
test lifetime_cap_cannot_be_exceeded() {
  let old = f.datum(0)
  let next = Datum { ..old, state: State { ..old.state, issued: 1001, outstanding: 1001 } }
  !issuance.controller_authorizes(old, Issue { items: [] }, f.reference, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 901), [f.owner], []))
}
test burning_does_not_restore_lifetime_capacity() {
  let old = f.datum(0)
  let old = Datum { ..old, state: State { ..old.state, issued: 1000, outstanding: 100 } }
  let next = Datum { ..old, state: State { ..old.state, issued: 1001, outstanding: 101 } }
  !issuance.controller_authorizes(old, Issue { items: [] }, f.reference, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 1), [f.owner], []))
}
test circulating_cap_can_reissue_burned_supply() {
  let old = f.datum(0)
  let old = Datum { ..old, state: State { ..old.state, rules: Rules { ..old.state.rules, lifetime_cap: False }, issued: 2000, outstanding: 100 } }
  let next = Datum { ..old, state: State { ..old.state, issued: 2100, outstanding: 200 } }
  issuance.controller_authorizes(old, Issue { items: [] }, f.reference, f.controller_tx(old, next, assets.from_asset(f.policy, #"0014df10525443", 100), [f.owner], []))
}
test pause_blocks_issuance() { let d = f.datum(0) let d = Datum { ..d, state: State { ..d.state, issuance_paused: True } } !issuance.controller_authorizes(d, Issue { items: [] }, f.reference, issue_tx()) }
test burn_remains_open_while_issuance_paused() {
  let d = f.datum(0)
  let d = Datum { ..d, state: State { ..d.state, issuance_paused: True } }
  let next = Datum { ..d, state: State { ..d.state, outstanding: 90 } }
  issuance.controller_authorizes(d, Burn, f.reference, f.controller_tx(d, next, assets.from_asset(f.policy, #"0014df10525443", -10), [], []))
}
test burn_rejects_positive_issuance() { !issuance.controller_authorizes(f.datum(0), Burn, f.reference, issue_tx()) }
test cannot_burn_an_unrelated_asset() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, outstanding: 90 } }
  !issuance.controller_authorizes(d, Burn, f.reference, f.controller_tx(d, next, assets.from_asset(f.policy, "OTHER", -10), [], []))
}
test reference_nft_cannot_be_burned() {
  let d = f.datum(0)
  !issuance.controller_authorizes(d, Burn, f.reference, f.controller_tx(d, d, assets.from_asset(f.policy, d.state.rules.state_name, -1), [f.owner], []))
}
test close_minting_is_permanent() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, minting_closed: True } }
  issuance.controller_authorizes(d, CloseMinting, f.reference, f.controller_tx(d, next, assets.zero, [f.owner], []))
}
test closed_issuance_cannot_restart() { let d = f.datum(0) let d = Datum { ..d, state: State { ..d.state, minting_closed: True } } !issuance.controller_authorizes(d, Issue { items: [] }, f.reference, issue_tx()) }
test roles_cannot_edit_metadata() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, metadata_mutable: False } }
  !issuance.controller_authorizes(d, UpdateMetadata { metadata: d.metadata, freeze: True }, f.reference, f.controller_tx(d, next, assets.zero, [f.other], []))
}
test owner_freezes_metadata() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, metadata_mutable: False } }
  issuance.controller_authorizes(d, UpdateMetadata { metadata: d.metadata, freeze: True }, f.reference, f.controller_tx(d, next, assets.zero, [f.owner], []))
}
test duplicate_roles_rejected() { !issuance.valid_minters([f.owner, f.owner]) }
test oversized_role_list_rejected() { !issuance.valid_minters([#"00"]) }
test two_step_ownership() {
  let d = f.datum(0)
  let pending = Datum { ..d, state: State { ..d.state, pending_owner: Some(f.other) } }
  let accepted = Datum { ..d, state: State { ..d.state, owner: Some(f.other) } }
  and {
    issuance.controller_authorizes(d, BeginOwnership { pending: Some(f.other) }, f.reference, f.controller_tx(d, pending, assets.zero, [f.owner], [])),
    issuance.controller_authorizes(pending, AcceptOwnership, f.reference, f.controller_tx(pending, accepted, assets.zero, [f.other], [])),
    !issuance.controller_authorizes(pending, AcceptOwnership, f.reference, f.controller_tx(pending, accepted, assets.zero, [f.owner], [])),
  }
}
test renounce_closes_issuance_roles_and_metadata() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, owner: None, pending_owner: None, minters: [], minting_closed: True, issuance_paused: False, metadata_mutable: False } }
  issuance.controller_authorizes(d, Renounce, f.reference, f.controller_tx(d, next, assets.zero, [f.owner], []))
}
test cannot_remove_state_ada() {
  let d = f.datum(0)
  let tx = issue_tx()
  expect [out] = tx.outputs
  !issuance.controller_authorizes(d, Issue { items: [] }, f.reference, Transaction { ..tx, outputs: [Output { ..out, value: assets.add(out.value, #"", #"", -1) }] })
}
test moving_controller_to_another_script_rejected() {
  let tx = issue_tx()
  expect [out] = tx.outputs
  !issuance.controller_authorizes(f.datum(0), Issue { items: [] }, f.reference, Transaction { ..tx, outputs: [Output { ..out, address: address.from_script(f.metadata_hash) }] })
}
test collection_issues_unique_cip68_pairs() {
  let d = f.datum(1)
  let next = Datum { ..d, state: State { ..d.state, issued: 1, outstanding: 1 } }
  let item = NftItem { recipient: address.from_verification_key(f.other), metadata: f.metadata(), frozen: False }
  let user_name = common.nft_name(common.nft_label, 1)
  let reference_name = common.nft_name(common.reference_label, 1)
  let metadata = MetadataDatum { metadata: item.metadata, version: 3, state: MetadataState { policy: f.policy, reference_name, controller_name: d.state.rules.state_name, controller_hash: f.controller_hash, frozen: False } }
  let user_output = Output { address: item.recipient, value: assets.from_lovelace(2000000) |> assets.add(f.policy, user_name, 1), datum: NoDatum, reference_script: None }
  let meta_output = Output { address: address.from_script(f.metadata_hash), value: assets.from_lovelace(3000000) |> assets.add(f.policy, reference_name, 1), datum: InlineDatum(metadata), reference_script: None }
  let mint = assets.from_asset(f.policy, user_name, 1) |> assets.add(f.policy, reference_name, 1)
  issuance.controller_authorizes(d, Issue { items: [item] }, f.reference, f.controller_tx(d, next, mint, [f.owner], [user_output, meta_output]))
}
fn genesis() -> (Configuration, Transaction) {
  let initial = f.datum(0)
  let config = Configuration { anchor: f.reference, creator: address.from_verification_key(f.owner), treasury: address.from_verification_key(f.other), recipient_lovelace: 10000000, deadline_ms: 300000, controller_hash: f.controller_hash, initial: Datum { ..initial, state: State { ..initial.state, policy: #"" } } }
  let fee = Output { address: config.treasury, value: assets.from_lovelace(10000000), datum: InlineDatum(builtin.b_data(f.policy)), reference_script: None }
  let tx = Transaction { ..transaction.placeholder, inputs: [Input { output_reference: f.reference, output: f.paid(0) }], outputs: [f.state_output(initial), f.paid(100), fee], mint: assets.from_asset(f.policy, initial.state.rules.state_name, 1) |> assets.add(f.policy, #"0014df10525443", 100), extra_signatories: [f.owner], validity_range: interval.between(100000, 200000) }
  (config, tx)
}
test genesis_atomic_fee_and_supply() { let (c, tx) = genesis() issuance.policy_authorizes(c, f.policy, tx) }
test genesis_requires_payment() {
  let (c, tx) = genesis()
  expect [a, b, _] = tx.outputs
  !issuance.policy_authorizes(c, f.policy, Transaction { ..tx, outputs: [a, b] })
}
test genesis_rejects_wrong_payment_tag() {
  let (c, tx) = genesis()
  expect [a, b, fee] = tx.outputs
  !issuance.policy_authorizes(c, f.policy, Transaction { ..tx, outputs: [a, b, Output { ..fee, datum: InlineDatum(builtin.b_data(f.other)) }] })
}
test genesis_cannot_replay_without_anchor() { let (c, tx) = genesis() !issuance.policy_authorizes(c, f.policy, Transaction { ..tx, inputs: [] }) }
test genesis_requires_creator_signature() { let (c, tx) = genesis() !issuance.policy_authorizes(c, f.policy, Transaction { ..tx, extra_signatories: [] }) }
test genesis_expiry_enforced() { let (c, tx) = genesis() !issuance.policy_authorizes(c, f.policy, Transaction { ..tx, validity_range: interval.between(100000, 300000) }) }
test paid_policy_requires_own_tag() fail {
  let (c, tx) = genesis()
  issuance.policy_authorizes(c, f.other, tx)
}
test owner_can_pause_issuance() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, issuance_paused: True } }
  issuance.controller_authorizes(d, SetPause { paused: True }, f.reference, f.controller_tx(d, next, assets.zero, [f.owner], []))
}
test owner_can_delegate_minting() {
  let d = f.datum(0)
  let next = Datum { ..d, state: State { ..d.state, minters: [f.other] } }
  issuance.controller_authorizes(d, SetMinters { minters: [f.other] }, f.reference, f.controller_tx(d, next, assets.zero, [f.owner], []))
}
test mutable_issuance_requires_current_controller() fail {
  let (c, _) = genesis()
  issuance.policy_authorizes(c, f.policy, transaction.placeholder)
}
