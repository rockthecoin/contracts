# RockTheCoin contracts

[![Contracts](https://github.com/rockthecoin/contracts/actions/workflows/contracts.yml/badge.svg)](https://github.com/rockthecoin/contracts/actions/workflows/contracts.yml)

Public smart-contract source for [RockTheCoin](https://www.rockthecoin.com): token and NFT creation, collections, distribution, liquidity tools, vesting, locks and optional Uniswap V4 or SunSwap V4 creator rewards.

This repository publishes contract packages and their verification tools.

## Find a deployed contract

- [Mainnet deployments and explorer links](docs/deployments.md)
- [Machine-readable deployment map](deployments.json)
- [Admin powers, creator permissions and fees](docs/permissions.md)
- [Version notes and compatibility](docs/releases.md)
- [Build and on-chain verification](docs/verification.md)
- [Solana controller build and verification](docs/solana-verification.md)
- [Avalanche V8 deployment and verification](docs/avalanche-verification.md)
- [Optimism V8 deployment and verification](docs/optimism-verification.md)
- [Native TRON releases, builds and verification](docs/tron-verification.md)
- [Native Cardano contracts and reference scripts](docs/cardano-verification.md)
- [Native Sui Move source, builds and permissions](docs/sui-verification.md)
- [Native Algorand programs, builds and mainnet verification](docs/algorand-suite.md)
- [Report a vulnerability privately](https://github.com/rockthecoin/contracts/security/advisories/new)

The deployment map covers Solana, Ethereum, BNB Chain, Base, Arbitrum One, Polygon, Avalanche, Optimism, TRON, Cardano, Sui and Algorand. Ethereum and BNB use advanced factory V6; Base, Arbitrum and Polygon use V7; Avalanche and Optimism use V8. TRON uses native V3 creation factories with V1 distribution and rewards contracts. Rewards hook versions also differ by network. Always select the address **and version** from the deployment map, rather than assuming the newest package is used everywhere.

## Packages

| Package | Purpose |
| --- | --- |
| `contracts/RockTheCoinFactory.sol`, `build/` | V2 basic fixed-supply ERC-20 tokens and single ERC-721 NFTs |
| `contracts/launch-v3/` | Earlier managed and taxable token factory |
| `contracts/launch-v4/`, `launch-v5/` | Historical advanced token, vesting and position-lock packages |
| `contracts/launch-v6/`, `launch-v7/`, `launch-v8/` | Configurable tokens, delegated roles, taxes, vesting and position locks; V8 protects vesting backing against excessive sender debits |
| `contracts/collections-v1/` | Creator-owned ERC-721 collections |
| `contracts/tools-v1/` | Atomic distribution and approved-protocol liquidity execution |
| `contracts/rewards-v1/` through `rewards-v3/` | Uniswap V4 creator rewards; V1 also includes the CREATE2 address helper |
| `contracts/solana-controller-v1/` | Immutable Solana mint caps, transfer-fee ceilings and vesting |
| `contracts/cardano-v1/`, `cardano-suite-v1/`, `cardano-suite-v2/` | Native Cardano issuance, collections, metadata, vesting and asset locks |
| `contracts/algorand-suite-v1/`, `algorand-token-v2/` | Immutable native ASA/Smart ASA controls, NFT collections, vesting and asset locks |
| `contracts/sui-suite-v1/`, `sui-creators-v2/` | Immutable Move library and unique configurable coin/NFT creator templates |
| `contracts/tron-suite-v1/`, `tron-suite-v2/`, `tron-suite-v3/` | Native TRON tokens, NFTs, collections, locks, distribution, SunSwap liquidity and rewards |

Each EVM and native TRON package retains its saved compiler input, ABI and bytecode. Dependency source contents are embedded in `standard-input.json`; they do not depend on the current contents of an upstream repository. `packages.json` pins compiler versions and artifact locations. `SHA256SUMS` fingerprints the published packages.

## Check locally

Use Node.js from `.nvmrc`:

```sh
npm ci --ignore-scripts
npm run verify:integrity
npm run verify:builds
npm test
```

EVM builds compile in memory and compare with the saved artifacts. Tests execute in an in-memory EVM and include payment rollback, quote replay protection, chain and payer binding, ownership, collection supply caps, delegated minting, vesting, distribution, protocol balances and creator rewards.

For Solana, create a Python virtual environment, install `requirements-test.txt`, and run `python tests/solana_controller.py`. Its LiteSVM fixtures exercise the published executable with SPL Token-2022 programs. All fixture keys are public test keys and must never be funded.

Cardano checks verify the original Aiken sources, script hashes and compiled validators. Its build instructions are in [Cardano verification](docs/cardano-verification.md).

Sui checks reproduce all library and creator modules and run 35 native Move tests. See [Sui verification](docs/sui-verification.md).

Algorand checks preserve the frozen Python/TEAL sources and reproduce all four AVM programs with PuyaPy 5.10.1. Read-only verification checks the three deployed apps and their canonical creation transactions. See [Algorand verification](docs/algorand-suite.md).

CI runs EVM reproduction and execution, Solana execution, pinned Solana/TRON rebuilds, Aiken checks/rebuilds and Sui Move tests/rebuilds. It has read-only repository permissions and does not deploy contracts, access a funded wallet or contact blockchain RPCs. Optional on-chain check scripts only read chain state.

## Verification and review limits

The dated [verification evidence](docs/verification/) records the contracts actually checked. A source match establishes which code is deployed; it does not establish that the code is free of vulnerabilities. These checks are project-maintained and are not an independent audit. No wallet provider endorsement or allowlist status is implied.

Published packages are preserved. Fixes require a new version; publishing or tagging code does not upgrade any deployed contract. Contributions must follow [CONTRIBUTING.md](CONTRIBUTING.md). RockTheCoin's Solidity/Solana/Sui code is MIT licensed; Cardano packages declare Apache-2.0. Preserve [third-party notices](THIRD_PARTY_NOTICES.md).
