use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/assets
use cardano/transaction.{InlineDatum, OutputReference, Transaction}

// Every quote has its own policy, identified by an input that can only be
// consumed once. No mint authority, metadata key or service key is retained.
pub type Configuration {
  anchor: OutputReference,
  creator: Address,
  treasury: Address,
  recipient_lovelace: Int,
  deadline_ms: Int,
  user_name: ByteArray,
  reference_name: ByteArray,
  supply: Int,
  metadata_hash: ByteArray,
  metadata_lock_hash: ByteArray,
}

pub fn authorizes(c: Configuration, policy: PolicyId, tx: Transaction) -> Bool {
  let minted = assets.tokens(tx.mint, policy)
  // Holders may burn their own assets. The locked reference NFT cannot be
  // spent, and this branch can never increase a circulating balance.
  if dict.values(minted) |> list.all(fn(quantity) { quantity < 0 }) {
    True
  } else {
    expect VerificationKey(creator_key) = c.creator.payment_credential
    and {
      c.supply > 0,
      c.recipient_lovelace >= 0,
      c.user_name != c.reference_name,
      dict.size(minted) == 2,
      assets.quantity_of(tx.mint, policy, c.user_name) == c.supply,
      assets.quantity_of(tx.mint, policy, c.reference_name) == 1,
      list.any(tx.inputs, fn(input) { input.output_reference == c.anchor }),
      list.has(tx.extra_signatories, creator_key),
      interval.is_entirely_before(tx.validity_range, c.deadline_ms),
      list.any(tx.outputs, fn(output) {
        and {
          output.address == c.creator,
          assets.quantity_of(output.value, policy, c.user_name) == c.supply,
        }
      }),
      list.any(tx.outputs, fn(output) {
        when output.datum is {
          InlineDatum(metadata) -> and {
            output.address.payment_credential == Script(c.metadata_lock_hash),
            output.address.stake_credential == None,
            assets.quantity_of(output.value, policy, c.reference_name) == 1,
            blake2b_256(builtin.serialise_data(metadata)) == c.metadata_hash,
          }
          _ -> False
        }
      }),
      c.recipient_lovelace == 0 || list.any(tx.outputs, fn(output) {
        when output.datum is {
          InlineDatum(tag) -> and {
            output.address == c.treasury,
            assets.lovelace_of(output.value) == c.recipient_lovelace,
            tag == builtin.b_data(policy),
          }
          _ -> False
        }
      }),
    }
  }
}

validator creation(configuration: Configuration) {
  mint(_redeemer: Data, policy: PolicyId, tx: Transaction) {
    authorizes(configuration, policy, tx)
  }
  else(_) { fail }
}

// A CIP-68 reference NFT locked here is immutable and cannot be redeemed,
// including its minimum ADA. There is no administrator or update path.
validator immutable_metadata {
  else(_) { fail }
}
