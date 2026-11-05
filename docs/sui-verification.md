# Native Sui contracts and verification

Sui mainnet uses one immutable seven-module Move library: authority, coin
controls, collections, Kiosk royalty rules, distribution, vesting and owned-object
locks. The [deployment map](../deployments.json) records the package, publishing
wallet, publication transaction and checkpoint.

Each creator publishes a distinct asset type in a separate package. Current
coins use the V1 coin template; NFTs and collections use the V2 template. The
original V1 NFT template is preserved for compatibility. Template constants are
placeholders: configuration requires replacing their typed values, preserving
a unique constant pool and updating constant-load indices. Both the library and
every creator package consume their UpgradeCap in their publication transaction.

## Offline source and artifact checks

Use Node 24 from `.nvmrc`:

```sh
npm ci --ignore-scripts
npm run verify:integrity
npm run verify:sui
```

These checks compare original Move files, source digests, published lock hashes
and all ten saved library/template modules. They make no RPC requests and never
overwrite published artifacts.

## Reproduce bytecode and run native tests

```sh
python3 scripts/install-sui.py
npm run verify:sui-builds
npm run test:sui
```

The installer downloads the official Sui mainnet 1.81.1 Linux x86-64 archive and
verifies its archive and executable SHA-256 values from
[`toolchains/sui.json`](../toolchains/sui.json). Alternatively set
`SUI=/absolute/path/to/sui`; the same checksum and version checks apply. The
framework revision is pinned to `e04cf9aa915cb6c069092733bebc3648755998e2`.
Builds can fetch that framework source; they do not access blockchain RPCs.

Builds and tests use disposable copies. Reproduction compares every module byte
and dependency list. The 35 native Move tests cover creator authority, delegated
roles, mint limits, regulation, revocation, metadata, royalty ceilings, lifetime
collection caps, initial NFT minting, holder metadata freezing, vesting and locks.

## Compare mainnet code

```sh
npm run verify:sui-chain
# Optional alternative HTTPS gRPC endpoint:
SUI_RPC=https://fullnode.mainnet.sui.io npm run verify:sui-chain
```

The command allows only Ledger `GetServiceInfo`, `GetObject` and `GetTransaction`.
It checks a fresh mainnet checkpoint, version-one package identity, all seven
stored module bytes, framework linkage, the checkpointed publication's digest
and sender, and its immediate `make_immutable` call. Only self-address references
are normalized; all other module code must match exactly. It contains no signing
or transaction-submission path.

The dated [mainnet evidence](../verification/sui-mainnet-2026-11-05.json) records
the successful check. [Unsigned customer simulations](../verification/sui-customer-simulations-2026-11-05.json)
cover 12 creation, distribution and vesting scenarios using that library.
Simulations created no on-chain assets and spent no wallet funds.

## Permissions and limits

The library has no platform owner, upgrade authority, recipient setting, quote
signer or global pause. Asset controls belong to the creator's retained
capabilities and delegated roles. Native service payment and the selected action
share the customer's programmable transaction; failure rolls back both, with
network gas remaining separate.

Ordinary Sui coins do not provide EVM transfer taxes, allowances, voting
checkpoints or universal wallet limits. Optional regulated coins follow Sui's
native deny-list and pause semantics. Kiosk royalties apply to policy-governed
trades; direct transfers do not enforce royalties. Updating an owned NFT needs
both its holder's object input and metadata permission. Locks preserve a fixed
beneficiary; locked liquidity positions must be released before management.

These project-maintained checks establish the checked source/code relationship
and selected behavior. They are not an independent security audit or wallet
provider endorsement.
