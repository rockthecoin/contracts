# Optimism mainnet verification

OP Mainnet uses chain ID **10**. **ETH** pays network costs and quoted service
fees. The six contracts are listed in [the deployment map](../deployments.json).
The advanced factory is **Builder V8** and creator rewards use **hook V3**.

On 2026-11-05 all six deployed runtimes matched their frozen artifacts, with only
compiler-declared constructor immutables normalized. The recorded owner was
`0x9493e58153c5c6647e67b18fef1c37ebd1c6ea79`. Recipients and quote signers matched,
and every contract was unpaused. Builder verification also checked the linked
token deployer. The hook matched OP's Uniswap V4 PoolManager, registered
ServiceTools address and permission bits 8260. Sourcify returned exact creation
and runtime matches for all six deployments.

All five ServiceTools targets were approved at a finalized block: the Uniswap V2
router, V3 and V4 position managers, Permit2 and the registered rewards hook.
OP L2 confirmations alone do not establish Ethereum settlement finality; these
checks used the RPC's finalized block tag. Owner-controlled settings may change
after the recorded check.

- [Runtime and constructor state](../verification/optimism-mainnet-2026-11-05.json)
- [Finalized configuration and protocol approvals](../verification/optimism-readiness-2026-11-05.json)
- [Source verification](../verification/optimism-source-2026-11-05.json)
- [Unsigned creation and distribution checks](../verification/optimism-customer-2026-11-05.json)
- [Native ETH liquidity plans](../verification/optimism-liquidity-2026-11-05.json)

Eight unsigned mainnet checks exercise five token presets, a single NFT, a
collection and native ETH distribution. RPC balance overrides are confined to
simulation. Uniswap V2/V3/V4 plans use native ETH and the registered ServiceTools
contract; plan checks do not claim that a funded pool was created. No funded
transaction was signed or broadcast for verification.

Standalone tests cover chain and payer binding, V8 quote-domain separation,
atomic ETH payment rollback, delegated minting, vesting backing and hostile
callbacks. OP fixtures use Osaka and a 16,777,216 transaction execution budget.
Existing contract source, compiler inputs and artifact bytes remain unchanged.

```sh
npm ci --ignore-scripts
npm run verify:integrity
npm run verify:builds
npm test
npm run verify:chain -- --chain optimism --rpc https://mainnet.optimism.io
npm run verify:source -- --chain optimism
```

These are project-maintained checks, not an independent audit. Reproducing a
build and identifying deployed source do not prove the absence of vulnerabilities.
