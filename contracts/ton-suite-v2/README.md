# TON native suite V2

A separately versioned security release of the six immutable Tolk 1.5.0 contracts. Only `SuiteFactory` needs an operator deployment. Jetton masters/wallets, NFT collections/items and individual vesting/lock escrows deploy for customers as needed. There is no code upgrade or operator withdrawal authority over customer assets.

V2 changes:

- Escrow payment recovery spends a conservatively measured bounced-payment credit plus the caller's processing budget. It preserves existing principal and surplus for the fixed beneficiary.
- NFT mint requests bind the expected collection index. A completed request cannot mint another index when replayed. Pending mint retries retain their original index, recipient, metadata and mutable setting.
- An item's initialization retry only repeats its original acknowledgement; it never overwrites later metadata. Metadata changes use a separate message and permanent freezes stay closed.
- NFT burn state survives a delayed service-payment bounce and recovery. Retrying payment never restores a burned NFT.
- Token and collection controls reject changes before authenticated launch.

The factory uses quote domain `0x52544332`, mainnet global ID `-239` and an Ed25519 authorization over the exact creator, receiving wallet, factory, quote ID, expiry, TON value and complete child code/data. Owner configuration and two-step ownership remain separate from asset-specific permissions. EUR prices are converted before authorization; the contracts receive a fixed native amount.

TON processes separate internal messages without a global rollback. The customer verifier checks exact committed creation, token delivery and successful service-payment receipts. Network costs can still be spent when an operation fails. Jetton/NFT escrows are deployed first and funded with a separate wallet approval. Standard jettons are required; custom token code may change transfer behavior. Marketplace royalties are advisory.

The unchanged V1 release and every saved V1 approval remain separate and verifiable. Registration and deployment do not enable services, change prices or publish TON. New creations use V2 after the operator deploys, registers and enables it.

```sh
node scripts/compile-ton-suite-v2.mjs --verify
node --test tests/ton*.test.mjs
```

`published.lock` freezes offered sources and exact artifacts. Further contract changes require a new version. See [setup and feature mapping](../../docs/ton-suite.md) and the [internal security review](../../docs/security/ton-suite-review-2026-11-09.md).
