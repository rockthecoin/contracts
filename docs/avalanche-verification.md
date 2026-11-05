# Avalanche C-Chain verification

Avalanche mainnet uses chain ID **43114** and **AVAX** for transaction costs and
quoted service fees. The six deployed contracts are listed in
[the deployment map](../deployments.json). The configurable token factory is
**Builder V8**; creator rewards use **hook V3**.

On 2026-11-05, all six runtimes matched their frozen artifacts, with only declared
constructor immutables normalized. Every deployment had the recorded owner
`0x9493e58153c5c6647e67b18fef1c37ebd1c6ea79`; fee recipients and quote signers
matched, and all services were unpaused. Factory verification also checked the
linked token deployer. The rewards hook matched Avalanche's Uniswap V4
PoolManager, the registered ServiceTools contract and hook permission bits 8260.

Sourcify returned **exact creation and runtime matches for all six deployments**.

All five ServiceTools targets were approved at a finalized block: Uniswap V2
router, V3 and V4 position managers, Permit2 and the registered rewards hook.
These are dated observations; contract owners can subsequently change settings.

- [Runtime comparison and constructor state](../verification/avalanche-mainnet-2026-11-05.json)
- [Finalized configuration and target checks](../verification/avalanche-readiness-2026-11-05.json)
- [Unsigned creation and distribution checks](../verification/avalanche-customer-2026-11-05.json)
- [Native AVAX liquidity plan checks](../verification/avalanche-liquidity-2026-11-05.json)
- [Source verification status](../verification/avalanche-source-2026-11-05.json)

The unsigned customer checks exercised fixed, meme, managed, taxable and custom
tokens, a single NFT, an NFT collection and native AVAX distribution against the
deployed factories. RPC balance overrides were confined to simulations. Uniswap
V2, V3 and V4 creation plans used native AVAX and the registered ServiceTools
address. These plan checks do not claim a funded pool was created. No wallet
transaction was signed or broadcast for verification.

Reproduce the independent checks:

```sh
npm ci --ignore-scripts
npm run verify:integrity
npm run verify:builds
npm test
npm run verify:chain -- --chain avalanche --rpc https://api.avax.network/ext/bc/C/rpc
npm run verify:source -- --chain avalanche
```

V8 preserves the original sources and compiler input. It enforces an outgoing
balance floor on both vesting payout paths; a token that charges an extra sender
fee cannot consume the remaining allocation or donated surplus. Accepted V5/V6/V7
assets and quote domains remain unchanged. These project-maintained checks are
not an independent audit.
