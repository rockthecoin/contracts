use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{Assets, Tokens}
use cardano/assets
use cardano/transaction.{InlineDatum, Input, Output, OutputReference, Transaction}
use cardano/transaction

pub const maximum_quantity: Int = 9223372036854775807
pub const reference_label: ByteArray = #"000643b0"
pub const nft_label: ByteArray = #"000de140"
pub const token_label: ByteArray = #"0014df10"
pub const collection_marker: ByteArray = "RockTheCoinCollection"

pub fn key_valid(key: ByteArray) -> Bool {
  bytearray.length(key) == 28 && key != #"00000000000000000000000000000000000000000000000000000000"
}
pub fn key_address(address: Address) -> Bool {
  when address.payment_credential is { VerificationKey(key) -> key_valid(key) _ -> False }
}
pub fn signed(key: Option<ByteArray>, tx: Transaction) -> Bool {
  when key is { Some(hash) -> key_valid(hash) && list.has(tx.extra_signatories, hash) None -> False }
}
pub fn script_address(address: Address, hash: ByteArray) -> Bool {
  address.payment_credential == Script(hash) && address.stake_credential == None
}
pub fn same_or_more(value: Assets, required: Assets) -> Bool {
  // Both ledger asset maps are ordered. Walk each policy/token list once;
  // repeated quantity_of lookups are quadratic and can make valid baskets
  // permanently exceed the execution budget of an immutable lock.
  policy_pairs_cover(assets.to_pairs(value), assets.to_pairs(required))
}
fn policy_pairs_cover(available: Pairs<ByteArray, Tokens>, required: Pairs<ByteArray, Tokens>) -> Bool {
  when required is {
    [] -> True
    [Pair(required_policy, required_tokens), ..remaining_required] -> when available is {
      [] -> False
      [Pair(policy, tokens), ..remaining] -> when bytearray.compare(policy, required_policy) is {
        Less -> policy_pairs_cover(remaining, required)
        Equal -> {
          // Whole-policy equality uses the ledger's native Data comparison.
          // Otherwise merge the ordered token pairs without repeated scans,
          // option allocation or a callback per asset.
          let actual: Data = tokens
          let expected: Data = required_tokens
          ( actual == expected || token_pairs_cover(dict.to_pairs(tokens), dict.to_pairs(required_tokens)) ) && policy_pairs_cover(remaining, remaining_required)
        }
        Greater -> False
      }
    }
  }
}
fn token_pairs_cover(available: Pairs<ByteArray, Int>, required: Pairs<ByteArray, Int>) -> Bool {
  when required is {
    [] -> True
    [Pair(required_name, required_quantity), ..remaining_required] -> when available is {
      [] -> False
      [Pair(name, quantity), ..remaining] ->
        if name == required_name {
          quantity >= required_quantity && token_pairs_cover(remaining, remaining_required)
        } else if builtin.less_than_bytearray(name, required_name) {
          token_pairs_cover(remaining, required)
        } else { False }
    }
  }
}
pub fn reference_value(value: Assets, policy: ByteArray, name: ByteArray) -> Bool {
  // Shared authority/metadata outputs hold only their unique reference NFT
  // and ADA. Permissionless holder burns must never insert other assets.
  assets.without_lovelace(value) == assets.from_asset(policy, name, 1)
}
pub fn one_script_input(tx: Transaction) -> Bool {
  // Prevent a single payout satisfying several different lock inputs, including
  // cross-validator combinations. Reference inputs and minting do not count.
  list.count(tx.inputs, fn(input) {
    when input.output.address.payment_credential is { Script(_) -> True _ -> False }
  }) == 1
}
pub fn own_input(tx: Transaction, reference: OutputReference) -> Input {
  expect Some(input) = transaction.find_input(tx.inputs, reference)
  input
}
pub fn datum(output: Output) -> Data {
  expect InlineDatum(data) = output.datum
  data
}
pub fn at_output(tx: Transaction, index: Int) -> Output {
  expect index >= 0
  expect Some(output) = list.at(tx.outputs, index)
  output
}
pub fn metadata_valid(data: Data) -> Bool {
  // CIP-68 metadata is a map. Bound the datum independently of node limits.
  expect fields: Pairs<Data, Data> = data
  let keys = list.map(fields, fn(entry) { let Pair(k, _) = entry expect key: ByteArray = k key })
  and {
    list.length(keys) <= 64,
    list.length(list.unique(keys)) == list.length(keys),
    list.all(keys, fn(key) { bytearray.length(key) > 0 && bytearray.length(key) <= 64 }),
    builtin.length_of_bytearray(builtin.serialise_data(data)) <= 4096,
  }
}
pub fn time_window(tx: Transaction, at_ms: Int) -> Bool {
  and {
    at_ms >= 0,
    !interval.is_empty(tx.validity_range),
    interval.includes(interval.between(at_ms, at_ms + 300000), tx.validity_range),
  }
}
pub fn nft_name(label: ByteArray, index: Int) -> ByteArray {
  bytearray.concat(label, bytearray.from_int_big_endian(index, 8))
}
