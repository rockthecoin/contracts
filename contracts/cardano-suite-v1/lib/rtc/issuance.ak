use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/assets
use cardano/transaction.{Output, OutputReference, Transaction}
use rtc/common

pub type Rules {
  kind: Int,
  base_name: ByteArray,
  state_name: ByteArray,
  maximum_supply: Int,
  lifetime_cap: Bool,
  burnable: Bool,
  pause_enabled: Bool,
  metadata_script: ByteArray,
}
pub type State {
  policy: PolicyId,
  rules: Rules,
  owner: Option<ByteArray>,
  pending_owner: Option<ByteArray>,
  minters: List<ByteArray>,
  issued: Int,
  outstanding: Int,
  minting_closed: Bool,
  issuance_paused: Bool,
  metadata_mutable: Bool,
}
// CIP-68 constructor 0: metadata map, version, arbitrary extra data.
pub type Datum { metadata: Data, version: Int, state: State }
pub type MetadataState {
  policy: PolicyId,
  reference_name: ByteArray,
  controller_name: ByteArray,
  controller_hash: ByteArray,
  frozen: Bool,
}
pub type MetadataDatum { metadata: Data, version: Int, state: MetadataState }
pub type NftItem { recipient: Address, metadata: Data, frozen: Bool }
pub type Action {
  Issue { items: List<NftItem> }
  Burn
  SetPause { paused: Bool }
  SetMinters { minters: List<ByteArray> }
  BeginOwnership { pending: Option<ByteArray> }
  AcceptOwnership
  CloseMinting
  UpdateMetadata { metadata: Data, freeze: Bool }
  Renounce
}
pub type Configuration {
  anchor: OutputReference,
  creator: Address,
  treasury: Address,
  recipient_lovelace: Int,
  deadline_ms: Int,
  controller_hash: ByteArray,
  initial: Datum,
}

pub fn valid_rules(r: Rules) -> Bool {
  and {
    r.maximum_supply > 0,
    r.maximum_supply <= common.maximum_quantity,
    if r.kind == 0 {
      and {
        bytearray.length(r.base_name) > 0,
        bytearray.length(r.base_name) <= 28,
        r.state_name == bytearray.concat(common.reference_label, r.base_name),
      }
    } else {
      and {
        r.kind == 1,
        r.base_name == #"",
        r.state_name == common.collection_marker,
        r.maximum_supply <= 1000000,
        r.lifetime_cap,
        bytearray.length(r.metadata_script) == 28,
      }
    },
  }
}
pub fn valid_minters(keys: List<ByteArray>) -> Bool {
  list.length(keys) <= 32 && list.length(list.unique(keys)) == list.length(keys) && list.all(keys, common.key_valid)
}
pub fn valid_state(d: Datum) -> Bool {
  let s = d.state
  and {
    d.version == 3,
    common.metadata_valid(d.metadata),
    bytearray.length(s.policy) == 28,
    valid_rules(s.rules),
    valid_minters(s.minters),
    s.issued >= 0,
    s.outstanding >= 0,
    s.outstanding <= s.issued,
    s.outstanding <= s.rules.maximum_supply,
    !s.rules.lifetime_cap || s.issued <= s.rules.maximum_supply,
    when s.owner is { Some(key) -> common.key_valid(key) None -> and { s.minting_closed, s.minters == [], s.pending_owner == None, !s.metadata_mutable, !s.issuance_paused } },
    when s.pending_owner is { Some(key) -> common.key_valid(key) None -> True },
    s.rules.pause_enabled || !s.issuance_paused,
  }
}
fn mint_authorized(s: State, tx: Transaction) -> Bool {
  common.signed(s.owner, tx) || list.any(s.minters, fn(key) { list.has(tx.extra_signatories, key) })
}
fn state_input(configuration: Configuration, policy: PolicyId, tx: Transaction) -> Bool {
  expect [input] = list.filter(tx.inputs, fn(input) {
    assets.quantity_of(input.output.value, policy, configuration.initial.state.rules.state_name) == 1
  })
  and {
    common.script_address(input.output.address, configuration.controller_hash),
    // The actual spend validator enforces the transition. The unique state NFT
    // cannot be forged, burned, duplicated or moved away from that validator.
    assets.quantity_of(tx.mint, policy, configuration.initial.state.rules.state_name) == 0,
  }
}
pub fn policy_authorizes(c: Configuration, policy: PolicyId, tx: Transaction) -> Bool {
  let minted = assets.tokens(tx.mint, policy)
  let marker = c.initial.state.rules.state_name
  if assets.quantity_of(tx.mint, policy, marker) == 1 {
    expect VerificationKey(creator_key) = c.creator.payment_credential
    let initial = Datum { ..c.initial, state: State { ..c.initial.state, policy } }
    let supply = initial.state.outstanding
    let user_name = bytearray.concat(common.token_label, initial.state.rules.base_name)
    and {
      common.key_address(c.creator),
      c.recipient_lovelace >= 0,
      bytearray.length(c.controller_hash) == 28,
      c.initial.state.policy == #"",
      valid_state(initial),
      initial.state.owner == Some(creator_key) || and { initial.state.owner == None, initial.state.minting_closed },
      initial.state.pending_owner == None,
      initial.state.issued == supply,
      if initial.state.rules.kind == 1 { supply == 0 } else { supply > 0 || !initial.state.minting_closed },
      dict.size(minted) == if supply == 0 { 1 } else { 2 },
      supply == 0 || assets.quantity_of(tx.mint, policy, user_name) == supply,
      list.any(tx.inputs, fn(input) { input.output_reference == c.anchor }),
      list.has(tx.extra_signatories, creator_key),
      !interval.is_empty(tx.validity_range),
      interval.is_entirely_before(tx.validity_range, c.deadline_ms),
      list.any(tx.outputs, fn(output) {
        and {
          common.script_address(output.address, c.controller_hash),
          assets.quantity_of(output.value, policy, marker) == 1,
          common.datum(output) == initial,
        }
      }),
      supply == 0 || list.any(tx.outputs, fn(output) { output.address == c.creator && assets.quantity_of(output.value, policy, user_name) == supply }),
      c.recipient_lovelace == 0 || list.any(tx.outputs, fn(output) {
        and {
          output.address == c.treasury,
          assets.lovelace_of(output.value) == c.recipient_lovelace,
          common.datum(output) == builtin.b_data(policy),
        }
      }),
    }
  } else {
    state_input(c, policy, tx)
  }
}

fn verify_items(items: List<NftItem>, s: State, controller_hash: ByteArray, tx: Transaction, index: Int) -> Bool {
  when items is {
    [] -> True
    [item, ..rest] -> {
      let user_name = common.nft_name(common.nft_label, index)
      let reference_name = common.nft_name(common.reference_label, index)
      let reference = MetadataDatum {
        metadata: item.metadata,
        version: 3,
        state: MetadataState { policy: s.policy, reference_name, controller_name: s.rules.state_name, controller_hash, frozen: item.frozen },
      }
      and {
        common.key_address(item.recipient),
        common.metadata_valid(item.metadata),
        s.metadata_mutable || item.frozen,
        assets.quantity_of(tx.mint, s.policy, user_name) == 1,
        assets.quantity_of(tx.mint, s.policy, reference_name) == 1,
        list.any(tx.outputs, fn(o) { o.address == item.recipient && assets.quantity_of(o.value, s.policy, user_name) == 1 }),
        list.any(tx.outputs, fn(o) {
          and {
            common.script_address(o.address, s.rules.metadata_script),
            assets.quantity_of(o.value, s.policy, reference_name) == 1,
            common.datum(o) == reference,
          }
        }),
        verify_items(rest, s, controller_hash, tx, index + 1),
      }
    }
  }
}
pub fn controller_authorizes(d: Datum, action: Action, reference: OutputReference, tx: Transaction) -> Bool {
  let own = common.own_input(tx, reference).output
  let s = d.state
  expect Script(controller_hash) = own.address.payment_credential
  expect [next_output] = list.filter(tx.outputs, fn(o) { assets.quantity_of(o.value, s.policy, s.rules.state_name) == 1 })
  expect next: Datum = common.datum(next_output)
  let minted = assets.tokens(tx.mint, s.policy)
  let no_mint = dict.is_empty(minted)
  and {
    valid_state(d),
    valid_state(next),
    assets.quantity_of(own.value, s.policy, s.rules.state_name) == 1,
    assets.quantity_of(tx.mint, s.policy, s.rules.state_name) == 0,
    next_output.address == own.address,
    common.same_or_more(next_output.value, own.value),
    when action is {
      Issue { items } -> {
        let quantity = if s.rules.kind == 0 { assets.quantity_of(tx.mint, s.policy, bytearray.concat(common.token_label, s.rules.base_name)) } else { list.length(items) }
        and {
          !s.minting_closed,
          !s.issuance_paused,
          mint_authorized(s, tx),
          quantity > 0,
          if s.rules.kind == 0 {
            items == [] && dict.size(minted) == 1
          } else {
            quantity <= 20 && dict.size(minted) == quantity * 2 && verify_items(items, s, controller_hash, tx, s.issued + 1)
          },
          next == Datum { ..d, state: State { ..s, issued: s.issued + quantity, outstanding: s.outstanding + quantity } },
        }
      }
      Burn -> {
        let total = dict.values(minted) |> list.foldl(0, fn(quantity, acc) { acc - quantity })
        and {
          s.rules.burnable,
          total > 0,
          list.all(dict.to_pairs(minted), fn(entry) {
            let Pair(name, quantity) = entry
            quantity < 0 && if s.rules.kind == 0 {
              name == bytearray.concat(common.token_label, s.rules.base_name)
            } else {
              bytearray.length(name) == 12 && bytearray.take(name, 4) == common.nft_label && bytearray.to_int_big_endian(bytearray.drop(name, 4)) <= s.issued
            }
          }),
          next == Datum { ..d, state: State { ..s, outstanding: s.outstanding - total } },
        }
      }
      SetPause { paused } -> no_mint && s.rules.pause_enabled && common.signed(s.owner, tx) && next == Datum { ..d, state: State { ..s, issuance_paused: paused } }
      SetMinters { minters } -> no_mint && common.signed(s.owner, tx) && valid_minters(minters) && next == Datum { ..d, state: State { ..s, minters } }
      BeginOwnership { pending } -> no_mint && common.signed(s.owner, tx) && next == Datum { ..d, state: State { ..s, pending_owner: pending } }
      AcceptOwnership -> no_mint && common.signed(s.pending_owner, tx) && next == Datum { ..d, state: State { ..s, owner: s.pending_owner, pending_owner: None } }
      CloseMinting -> no_mint && common.signed(s.owner, tx) && next == Datum { ..d, state: State { ..s, minting_closed: True } }
      UpdateMetadata { metadata, freeze } -> no_mint && s.metadata_mutable && common.signed(s.owner, tx) && next == Datum { metadata, version: d.version, state: State { ..s, metadata_mutable: !freeze } }
      Renounce -> no_mint && common.signed(s.owner, tx) && next == Datum { ..d, state: State { ..s, owner: None, pending_owner: None, minters: [], minting_closed: True, issuance_paused: False, metadata_mutable: False } }
    },
  }
}
