# TON native suite V1

Six immutable Tolk 1.5 contracts: a shared `SuiteFactory`, `JettonMaster`, `JettonWallet`, `NftCollection`, `NftItem` and `Vesting`. The operator deploys only the factory. Asset-specific contracts deploy during customer creation; each escrow has its own address and fixed beneficiary. There is no code-upgrade or operator asset-withdrawal entrypoint.

The factory checks an Ed25519 authorization over the creator, factory, receiving wallet, quote ID, expiry, TON value and complete child code/data cells. It accepts launches only on TON mainnet (`global_id = -239`). EUR pricing stays outside the contracts; an authorization fixes its native TON amount. The owner can change the receiving wallet, quote public key and new-launch pause, or nominate a successor who must accept ownership.

Creation fees remain in the child until initialization and, for jettons, the initial wallet-credit acknowledgement. A bounced fee remains recoverable; retry cannot mint again. Factory acknowledgements are idempotent. TON provides no global rollback across the message tree. Confirmation therefore checks original raw wallet, creation, delivery and payment receipts. Network costs can be spent even when creation fails.

Jettons retain the creator's chosen mint cap, lifetime cap, burn flag, editable metadata, issuance pause, delegated roles and individual wallet-freezing authority. Ownership uses two steps; acceptance clears roles. Renunciation cannot strand an issuance pause or discard the ability to unfreeze holders. These are standard jettons, without transfer taxes, universal transfer pause, EVM allowances/permit or historical governance checkpoints.

NFT collections enforce a lifetime cap, per-item indexes, mint/metadata/royalty roles, immutable choices and TEP-66 advisory royalties. Item metadata freezing is permanent. Failed child mint requests retain their original index for recovery. NFT transfers do not enforce marketplace royalties.

Escrows support TON, standard jettons, fungible LP tokens and NFT time locks. Native TON funds during launch; jetton/NFT funding follows a separately reviewed deployment and receive-address discovery. Funding, not an empty escrow deployment, releases its service fee. Releases preserve unvested principal and donated surplus; only the fixed beneficiary can recover matured surplus. An expired unfunded escrow can return the reserved service payment, and late or mistaken deposits remain recoverable by its original creator. Gas-budget refunds preserve existing escrow collateral.

## Reproduce

```sh
node scripts/compile-ton-suite.mjs --verify
node --test tests/ton*.test.mjs
```

`published.lock` freezes the sources and artifacts offered in God. Future behavior changes need a new release; do not rebuild over V1. Existing basic `ton-v1` contracts, saved approvals and receipt formats remain separate and unchanged. See [TON setup and feature mapping](../../docs/ton-suite.md).
