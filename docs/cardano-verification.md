# Native Cardano contracts and references

Cardano mainnet uses ADA for network fees. Tokens and NFTs are native ledger
assets. Each creation instantiates its own minting policy; there is no shared
ERC-20 factory address. Advanced assets use the current V2 controller and metadata
validators. Original single NFTs use the separate `cardano-v1` package.

## Source packages

| Package | Use |
| --- | --- |
| [`cardano-v1`](../contracts/cardano-v1) | Original fixed-supply tokens and single NFTs, immutable metadata and holder burns |
| [`cardano-suite-v1`](../contracts/cardano-suite-v1) | Historical advanced validators, retained for compatibility |
| [`cardano-suite-v2`](../contracts/cardano-suite-v2) | Current capped tokens, collections, CIP-68 item metadata, vesting and native-asset locks |

All three target Plutus V3 with Aiken **v1.1.24+bacbeb3** and stdlib **v4.0.0**.
The [compiler pin](../toolchains/aiken.json) includes the official release URL,
archive checksum and binary checksum. Each package contains its original Aiken
source, tests, blueprint, compiled script bytes and published hash lock. Cardano
packages declare Apache-2.0; see their package licenses.

V2 prevents unrelated assets from contaminating authority/metadata outputs and
uses bounded value comparisons for large native-asset baskets. V1 and V2 bytes
remain separate. Publishing a V2 reference does not upgrade an existing V1 asset.

## Reproduce the validators

From the repository root:

```sh
python3 scripts/verify-cardano.py
python3 scripts/install-aiken.py
python3 scripts/rebuild-cardano.py
```

The offline verifier checks source and artifact SHA-256 values, blueprint matches
and native Plutus V3 BLAKE2b-224 script hashes. Rebuilds run the Aiken tests and
compare all compiled validator bytes and hashes in temporary copies. The offered
contract files are never rebuilt in place. Use `AIKEN=/absolute/path/to/aiken` to
select an already installed binary with the exact pinned checksum.

## Verify the published references

The [deployment map](../deployments.json) records four CIP-33 V2 reference outputs:
controller, item metadata, vesting and asset lock. These are reusable copies of
validator code. They are distinct from customer controller state, metadata NFTs
and locked assets. The issuance-policy template is parameterized per creator,
so its template hash is not a deployed customer policy ID.

```sh
python3 scripts/verify-cardano-chain.py
```

This optional command only reads the public Koios mainnet API. It checks network
identity, current unspent reference outputs, exact script bytes/hashes, publishing
address and at least six block confirmations. It cannot sign or submit a
transaction. Dated results are in [Cardano evidence](../verification/cardano-mainnet-2026-11-03.json).

A reference output holds a minimum ADA deposit. Its publishing wallet can spend
that output and reclaim the ADA, removing that reusable copy. This does not
change existing asset rules or give the publisher control over customer assets.
A transaction may instead include the original script bytes if its size permits.
Reference availability must be checked before building a transaction.

## Liquidity

RockTheCoin integrates Minswap V2 pool creation and deposit/withdrawal orders.
Those operations use Minswap's existing protocol scripts. They are not additional
RockTheCoin contracts. Orders have explicit minimum amounts, a batcher fee,
returnable order deposit, owner cancellation and separate execution status.
LP tokens can use the published vesting or asset-lock validators.

Unsigned customer scenarios were evaluated using the actual mainnet reference
outputs. Synthetic supplemental inputs were used for testing; no funded wallet
was signed and no test transaction was broadcast. See the dated evidence for the
scope. Source matching and project-maintained tests are not an independent audit.
