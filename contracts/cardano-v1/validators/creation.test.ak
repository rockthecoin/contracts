use aiken/builtin
use aiken/crypto.{blake2b_256}
use aiken/interval
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, NoDatum, Output, OutputReference}
use cardano/transaction
use creation.{Configuration, authorizes}

const policy = #"11111111111111111111111111111111111111111111111111111111"
const creator_key = #"22222222222222222222222222222222222222222222222222222222"
const treasury_key = #"33333333333333333333333333333333333333333333333333333333"
const lock = #"44444444444444444444444444444444444444444444444444444444"

fn configuration() -> Configuration {
  Configuration {
    anchor: OutputReference { transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", output_index: 0 },
    creator: address.from_verification_key(creator_key),
    treasury: address.from_verification_key(treasury_key),
    recipient_lovelace: 10000000,
    deadline_ms: 180000,
    user_name: #"0014df10525443",
    reference_name: #"000643b0525443",
    supply: 100000000,
    metadata_hash: blake2b_256(builtin.serialise_data(builtin.b_data(#"727463"))),
    metadata_lock_hash: lock,
  }
}

fn creation_tx() -> transaction.Transaction {
  let c = configuration()
  let user = Output { address: c.creator, value: assets.from_lovelace(2000000) |> assets.add(policy, c.user_name, c.supply), datum: NoDatum, reference_script: None }
  let metadata = Output { address: address.from_script(lock), value: assets.from_lovelace(2000000) |> assets.add(policy, c.reference_name, 1), datum: InlineDatum(builtin.b_data(#"727463")), reference_script: None }
  let fee = Output { address: c.treasury, value: assets.from_lovelace(c.recipient_lovelace), datum: InlineDatum(builtin.b_data(policy)), reference_script: None }
  transaction.Transaction {
    ..transaction.placeholder,
    inputs: [transaction.Input { output_reference: c.anchor, output: user }],
    outputs: [user, metadata, fee],
    mint: assets.from_asset(policy, c.user_name, c.supply) |> assets.add(policy, c.reference_name, 1),
    validity_range: interval.between(0, 179000),
    extra_signatories: [creator_key],
  }
}

test creation_and_service_payment() { authorizes(configuration(), policy, creation_tx()) }
test free_creation() {
  let c = configuration()
  let tx = creation_tx()
  authorizes(Configuration { ..c, recipient_lovelace: 0 }, policy, transaction.Transaction { ..tx, outputs: [tx.outputs |> list_at(0), tx.outputs |> list_at(1)] })
}
fn list_at(xs: List<Output>, index: Int) -> Output {
  expect [a, b, c] = xs
  when index is { 0 -> a 1 -> b _ -> c }
}
test missing_payment() {
  let tx = creation_tx()
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, outputs: [list_at(tx.outputs, 0), list_at(tx.outputs, 1)] })
}
test wrong_payment_tag() {
  let tx = creation_tx()
  let fee = list_at(tx.outputs, 2)
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, outputs: [list_at(tx.outputs, 0), list_at(tx.outputs, 1), Output { ..fee, datum: InlineDatum(builtin.b_data(lock)) }] })
}
test wrong_payment_amount() {
  let tx = creation_tx()
  let fee = list_at(tx.outputs, 2)
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, outputs: [list_at(tx.outputs, 0), list_at(tx.outputs, 1), Output { ..fee, value: assets.from_lovelace(9999999) }] })
}
test changed_supply() {
  let c = configuration()
  let tx = creation_tx()
  !authorizes(c, policy, transaction.Transaction { ..tx, mint: assets.from_asset(policy, c.user_name, c.supply + 1) |> assets.add(policy, c.reference_name, 1) })
}
test replay_without_anchor() {
  let tx = creation_tx()
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, inputs: [] })
}
test missing_creator_approval() {
  let tx = creation_tx()
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, extra_signatories: [] })
}
test expired_quote() {
  let tx = creation_tx()
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, validity_range: interval.between(0, 180001) })
}
test metadata_cannot_change() {
  let tx = creation_tx()
  let reference = list_at(tx.outputs, 1)
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, outputs: [list_at(tx.outputs, 0), Output { ..reference, datum: InlineDatum(builtin.b_data(#"00")) }, list_at(tx.outputs, 2)] })
}
test no_additional_asset() {
  let tx = creation_tx()
  !authorizes(configuration(), policy, transaction.Transaction { ..tx, mint: tx.mint |> assets.add(policy, #"00", 1) })
}
test holder_burn_allowed() {
  let tx = transaction.Transaction { ..transaction.placeholder, mint: assets.from_asset(policy, configuration().user_name, -1) }
  authorizes(configuration(), policy, tx)
}
test burn_cannot_mint_another_asset() {
  let tx = transaction.Transaction { ..transaction.placeholder, mint: assets.from_asset(policy, configuration().user_name, -1) |> assets.add(policy, #"00", 1) }
  !authorizes(configuration(), policy, tx)
}
