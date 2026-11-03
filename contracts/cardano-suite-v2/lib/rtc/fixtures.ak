use aiken/builtin
use aiken/interval
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, OutputReference, Transaction}
use cardano/transaction
use rtc/common
use rtc/issuance.{Datum, Rules, State}

pub const policy: ByteArray = #"11111111111111111111111111111111111111111111111111111111"
pub const owner: ByteArray = #"22222222222222222222222222222222222222222222222222222222"
pub const other: ByteArray = #"33333333333333333333333333333333333333333333333333333333"
pub const controller_hash: ByteArray = #"44444444444444444444444444444444444444444444444444444444"
pub const metadata_hash: ByteArray = #"55555555555555555555555555555555555555555555555555555555"
pub const reference: OutputReference = OutputReference { transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", output_index: 0 }
pub fn metadata() -> Data { builtin.map_data([Pair(builtin.b_data("name"), builtin.b_data("RockTheCoin"))]) }
pub fn datum(kind: Int) -> Datum {
  Datum {
    metadata: metadata(),
    version: 3,
    state: State {
      policy,
      rules: Rules {
        kind,
        base_name: if kind == 0 { "RTC" } else { #"" },
        state_name: if kind == 0 { #"000643b0525443" } else { common.collection_marker },
        maximum_supply: 1000,
        lifetime_cap: True,
        burnable: True,
        pause_enabled: True,
        metadata_script: metadata_hash,
      },
      owner: Some(owner),
      pending_owner: None,
      minters: [],
      issued: if kind == 0 { 100 } else { 0 },
      outstanding: if kind == 0 { 100 } else { 0 },
      minting_closed: False,
      issuance_paused: False,
      metadata_mutable: True,
    },
  }
}
pub fn state_output(d: Datum) -> Output {
  Output { address: address.from_script(controller_hash), value: assets.from_lovelace(3000000) |> assets.add(policy, d.state.rules.state_name, 1), datum: InlineDatum(d), reference_script: None }
}
pub fn controller_tx(old: Datum, next: Datum, mint: assets.Assets, signers: List<ByteArray>, outputs: List<Output>) -> Transaction {
  Transaction { ..transaction.placeholder, inputs: [Input { output_reference: reference, output: state_output(old) }], outputs: [state_output(next), ..outputs], mint, extra_signatories: signers, validity_range: interval.between(100000, 200000) }
}
pub fn paid(quantity: Int) -> Output {
  Output { address: address.from_verification_key(owner), value: assets.from_lovelace(2000000) |> assets.add(policy, #"0014df10525443", quantity), datum: NoDatum, reference_script: None }
}
