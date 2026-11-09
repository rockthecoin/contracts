# TON contracts and verification

RockTheCoin uses one shared **TON suite V2 factory** on TON mainnet. The native
coin is **Gram (GRAM), formerly Toncoin (TON)**; the blockchain remains TON.

| Contract | Mainnet address |
| --- | --- |
| SuiteFactory V2 | [`0:df908e5b24803ebc41b7b07ef374c8098385199c3203e67fae48fb67deaa9837`](https://tonviewer.com/0:df908e5b24803ebc41b7b07ef374c8098385199c3203e67fae48fb67deaa9837) |

The owner and receiving wallet is
`UQAM3s7c0EiQNJU2hIyY8Nxirw2Xk-1pXiIKNK1DBi3cYe_X`, equivalent to
`0:0cdecedcd04890349536848c98f0dc62af0d9793ed695e220a34ad43062ddc61`.
The [deployment map](../deployments.json) records the public quote signer,
original owner transaction and separate factory initialization transaction.

## Contracts and permissions

Both versioned packages retain SuiteFactory, JettonMaster, JettonWallet,
NftCollection, NftItem and Vesting. V1 is historical; use V2 for new deployments.
Only SuiteFactory has a shared operator deployment. Other contracts deploy for
each customer's asset or escrow. Neither release has a code-upgrade entrypoint.

The factory owner can change the receiving wallet and quote public key, pause
new launches, or nominate a successor who must accept. These controls grant no
withdrawal authority over customer tokens or escrow principal.

Jetton creators choose fixed supply or retain capped minting, metadata editing,
issuance pause, roles and individual wallet freezing. Issuance pause does not
pause ordinary transfers. These templates offer no transfer taxes, EVM permit
signatures or historical voting checkpoints.

NFT collections have lifetime caps, indexed minting and optional metadata and
royalty controls. TEP-66 royalties are advisory for marketplaces. Vesting and
locks have a fixed beneficiary. GRAM can fund an escrow at creation; jettons
and NFTs require a separate funding transaction after address verification.

Liquidity uses existing STON.fi CPI V2.2 protocol contracts. No additional
RockTheCoin operator deployment is needed. STON.fi is a separate protocol,
not a contract package published here.

## Payment and settlement

Ed25519 authorization binds the exact native amount, creator, receiving wallet,
factory, expiry and complete child code/data. V2 uses domain `0x52544332` and
accepts launches only on mainnet global ID `-239`.

TON messages settle asynchronously, without a global rollback across contracts.
Initialization and jetton delivery acknowledgements precede payment. A bounced
payment can need recovery; network costs may already have been spent. The
original wallet transaction and linked creation, delivery and payment receipts
are required to confirm success. A callback or emulation alone is insufficient.

## Reproduce and verify

```sh
npm ci --ignore-scripts
npm run verify:ton
npm run verify:ton-builds
npm run test:ton
npm run verify:ton-chain
```

The compiler is pinned to `@ton/tolk-js` **1.5.0**. Reproduction compares code
cells, ABIs, source bundles and frozen files without overwriting artifacts.
`published.lock` and `SHA256SUMS` preserve the original release bytes.

Standalone TVM tests cover token/NFT/collection creation, fees, replay,
signature/payer/expiry binding, owner configuration, collection indexes and
fixed-beneficiary vesting. They use synthetic balances and public test keys.
The fixed public mainnet test configuration is a dated fixture, not a live fee
estimate. Never fund fixture addresses.

`verify:ton-chain` performs public reads only: fresh mainnet identity, exact
factory code and initialization, owner, receiving wallet, signer and original
parent/child message hash. See [dated evidence](verification/ton-mainnet-check.json)
and [V2 review notes](security/ton-suite-review-2026-11-09.md). Settings can change
after the recorded block. These are project-maintained checks, not an
independent audit or a wallet-provider endorsement.
