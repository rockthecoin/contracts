# Bitcoin Runes and Ordinals

Bitcoin support uses [protocol V1](../contracts/bitcoin-protocol-v1), rather than
a shared deployed factory. Its SHA-256 manifest and exact dependency lock are
published beside the source. Each creation commits to a unique Taproot tree and
then reveals the Rune etching or Ordinal inscription.

## Verify the published source

From the repository root:

```sh
node scripts/verify-bitcoin.mjs
npm ci --ignore-scripts --prefix contracts/bitcoin-protocol-v1
npm run test:bitcoin
```

The 16 protocol tests use deterministic fixture keys and synthetic previous
transactions. They cover native/nested SegWit and Taproot signatures, exact fee
outputs, tamper rejection, parent return, inscription sat placement, Rune change,
public mint bounds, separate artwork outputs and customer refunds. They do not
contact blockchain data services or broadcast transactions. Never fund fixture
keys. No funded customer creation was submitted as part of these protocol tests.

`verify-bitcoin.mjs` compares every frozen file hash and the embedded source
bundle. The dependency lock fixes the exact reviewed cryptographic libraries.

## Creation, payment and recovery

The creation leaf requires both the customer and service Schnorr signatures with
SIGHASH_ALL. The service signature binds the exact reveal, including its BTC
service-fee output. The other leaf permits a customer-only refund of an unused
commit, without publishing the inscription or Rune commitment. The internal key
is an unspendable NUMS point. The service key has no unilateral withdrawal path.

Both original customer approvals are saved before the commit is relayed. Named
Runes require six commit confirmations. Inscriptions wait for one. Exact raw
transactions, Bitcoin inclusion and the Ord result must be verified separately:
Bitcoin consensus does not itself guarantee that a Rune etching or mint is valid.
Name availability is not a reservation. A service-fee refund for an invalid
included creation is a separately approved operator transaction; spent miner
fees cannot be reversed by this script.

Transfers protect all verified Rune balances and inscription sat positions.
Unselected Rune change has its own output, separate from ordinary BTC change.
Rune artwork also uses a separate output. A child inscription spends and returns
its parent's complete output before the new child output.

Read-only data may come from public Esplora and Ord endpoints; the pure protocol
package contains no network client. Null or missing asset data must not be treated
as ordinary funding. There is no UniSat/Ordiscan credential or managed etching
provider requirement.

The source supports immutable Rune mint terms and Ordinal content. It does not
add issuer taxes, owner mint controls, enforced royalties, AMM pools, BRC-20 or
Alkanes. Content is bounded at 128 KiB and runestone scripts at 83 bytes for
conservative relay compatibility. Original approvals must keep using their
original transaction and script bytes; later behavior changes require a new
version.
