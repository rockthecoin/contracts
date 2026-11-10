# RockTheCoin Bitcoin protocol V1

Native mainnet transaction templates for Runes and Ordinals. Bitcoin has no
shared RockTheCoin factory deployment: each creation commits to its own Taproot
script, then reveals its Rune etching or inscription.

## What the source does

- Fixed-supply and meme Runes; optional public mint amount, cap and block windows.
- Ordinal content and CBOR metadata; parent/child provenance with parent return.
- Ordinary BTC distribution; Rune minting, transfers, multisending and burns;
  individual inscription transfers preserving the inscription sat position.
- SegWit, nested SegWit and Taproot funding with original prevout validation.
- Strict signed PSBT and raw transaction checks, including SIGHASH_ALL binding.
- Customer-controlled commit refunds and separately approved fee adjustments.

It has no HTTP client, wallet integration, broadcast code, customer database,
operator configuration or private keys. Input asset proofs must be obtained and
validated by the caller; this pure library does not independently verify an Ord
index or mainnet inclusion.

## Creation and refund scripts

The Taproot tree uses an unspendable NUMS internal key and two script leaves:

```
creation: <unique intent> DROP <customer key> CHECKSIGVERIFY <service key> CHECKSIG
          [unexecuted Rune commitment / Ordinal envelope]
refund:   <customer key> CHECKSIG
```

The service signs the exact reveal outputs, including the service-fee recipient
and amount. Its key cannot spend the commit alone. The customer also signs the
reveal; both original approvals should be persisted before relaying the commit.
The refund needs only the customer key and contains neither a Rune commitment nor
an inscription envelope. It returns unused commit funds less the refund miner
fee. Keep the original PSBT, control block and outpoint for independent recovery.

Named Runes require six commit confirmations. The initial inscription flow waits
for one. Rune name availability is a check, not a reservation. Competing etchings,
mint exhaustion, miner policy and reorgs remain possible: Bitcoin inclusion alone
does not prove an overlay asset is valid. Callers must separately verify the
confirmed Ord result and exact BTC service payment. A service-fee refund for an
invalid included creation is a separately approved operator transaction, not an
automatic Bitcoin consensus reversal. Miner fees already spent are not refundable.

Rune artwork has a distinct 546-sat inscription output; its Rune allocation uses
another output. Parent collections return the complete parent output before the
new child's output. Rune transfers send all unselected and excess Rune balances
to a dedicated asset-change output, separate from ordinary BTC change.

## Bounds and compatibility

Mainnet only. Content up to 128 KiB; conservative 546-sat output floor; 100,000-vB
transaction bound; runestone scripts at most 83 bytes for conservative relay
compatibility. Large Rune recipient lists or unusually large mint terms can need
smaller batches. Amounts are exact integer strings; Rune values use uint128.

Asset-bearing outputs cannot fund ordinary BTC transactions. Rune tools reject
inputs containing inscriptions; inscription transfers require one inscription and
no Runes. Consolidate or split unusual mixed outputs with an appropriate asset
wallet before using these tools. These templates do not add BRC-20, Alkanes, AMM
pools, issuer admin controls, transfer taxes, royalties or arbitrary contracts.

## Reproduce the checks

Use Node 24 and the exact dependency lockfile:

```sh
npm ci --ignore-scripts
npm test
```

Tests use deterministic keys and synthetic previous transactions that have never
existed on mainnet. Never fund those keys. No test connects to a node or relays a
transaction. `published.lock` binds this release's reviewed files to SHA-256
hashes. Future behavior changes require another version; original approvals must
continue to use their original source and transaction bytes.

Protocol references: [Runes](https://docs.ordinals.com/runes/specification.html),
[Ordinal provenance](https://docs.ordinals.com/inscriptions/provenance.html),
[BIP 341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki),
[BIP 342](https://github.com/bitcoin/bips/blob/master/bip-0342.mediawiki).
