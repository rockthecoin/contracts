# Verify source and deployments

## Reproduce the EVM artifacts

Run `npm ci --ignore-scripts`, `npm run verify:integrity`, then `npm run verify:builds`. Each saved standard JSON input includes compiler settings and dependency sources. Compiler versions are pinned in `packages.json` and the npm lockfile. The check compares ABI, creation code and deployed runtime for every saved artifact. Compiler AST identifiers may differ, so immutable-reference checks compare their grouped byte locations.

Build verification compiles in memory. It never writes over published inputs or artifacts.

## Compare EVM mainnet code

Choose a public RPC for the network you want to inspect:

```sh
npm run verify:chain -- --chain ethereum --rpc YOUR_HTTPS_RPC_URL
```

Use `bnb`, `base`, `polygon` or `arbitrum` for the other live EVM networks. The script checks chain identity and compares each runtime at a recorded block number. Only compiler-declared immutable-reference slots are masked, and repeated occurrences of an immutable must agree. Owner, recipient, signer and pause getters are recorded where supported. The script never signs or submits a transaction.

The checked snapshot is in [evm-mainnet-check.json](verification/evm-mainnet-check.json). Addresses can share a value on different chains; always check both the network and address.

## Explorer and Sourcify verification

An independent bytecode comparison and a third-party source-verification badge are separate checks. Explorer URLs in the deployment map identify the addresses; a link alone does not imply that an explorer has verified source.

On 2026-11-02, Sourcify V2 returned `exact_match` for both creation and runtime code for all 31 EVM contracts in this snapshot. [The dated source-verification report](verification/sourcify-source-status.json) includes each public verification URL. This does not imply that every other explorer has independently updated its source page.

The saved `standard-input.json` can be submitted as Solidity standard JSON with the package's exact compiler, contract identifier and original constructor arguments. Do not change compiler settings to make a source page look newer. Verification of an existing deployment does not require redeploying it.

Sourcify V2 offers public [source-verification APIs](https://docs.sourcify.dev/docs/api/). Etherscan-compatible explorers may require an API key. Verification status, where checked, is recorded separately from the runtime comparison.

Run `npm run verify:source` to look up current Sourcify status without changing anything. Adding `-- --submit` explicitly submits the saved compiler input for any missing source verification. This is source publication, not a blockchain transaction.

## Interpreting a result

A matching build proves the published input produces the saved artifact. A matching runtime proves the checked address uses the expected code, allowing only its documented immutable constructor values. Neither result is an independent security audit. Saved owner and service settings can change after the recorded block.
