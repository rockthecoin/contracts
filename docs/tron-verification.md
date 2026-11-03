# TRON contracts

TRON mainnet uses native TVM contracts and TRX for fees. Ethereum compiler builds
cannot reproduce these packages. The deployment map records all five live
contracts, their versions and transaction IDs.

- `tron-suite-v3`: basic token and single NFT factory, advanced token factory,
  collection factory, and their fixed implementations, vesting wallets and locks.
- `tron-suite-v1`: distribution/liquidity ServiceTools and the SunSwap V4 reward
  hook. The earlier basic, advanced and collection packages are retained for
  historical verification.
- `tron-suite-v2`: historical advanced-factory vesting security release.

New V3 assets are 45-byte clones. Each clone embeds one fixed implementation
address and has separate balances, permissions and metadata. There is no
implementation upgrade mechanism. Implementations have locked initialization
and are permanently bound to their factory or token deployer.

## Reproduce native bytecode

Use Linux x86-64, Python 3 and the repository's pinned Node.js version:

```sh
npm ci --ignore-scripts
python3 scripts/install-tron-compiler.py
npm run verify:integrity
npm run verify:tron-builds
```

The installer downloads the official TRON Solidity `0.8.31+commit.c2812a3d`
binary from the pinned upstream commit and checks SHA-256 before execution.
Set `TRON_SOLC` to use an existing binary with the exact same hash.
The saved compiler inputs retain Cancun, viaIR, 200 optimizer runs and the
explicit Yul sequence excluding LoadResolver and EqualStoreEliminator.
Reproduction compares creation bytecode, runtime, ABI and immutable references
without changing published artifacts.

## Check mainnet deployments

```sh
npm run verify:tron-chain
# Optional live SunSwap execution; creates no persistent contracts:
node scripts/simulate-tron-sunswap.mjs
```

This optional read-only check uses public TRON RPC endpoints. It checks mainnet
genesis, solidified successful deployment receipts, exact constructor data,
factory and dependency runtimes, fixed initializer/factory bindings, owners,
receiving wallets, signers, pause states and approved protocol targets. It never
requests a private key, signs a transaction or broadcasts one.

## SunSwap compatibility

SunSwap V2 and V3 retain the relevant Uniswap-style router and NFT-position
interfaces. SunSwap V4 uses a different PoolKey containing `bytes32 parameters`.
Tick spacing occupies bits 16–39; hook permissions occupy the lower 16 bits.
The RockTheCoin hook uses bitmap `2177` and needs no Ethereum CREATE2 helper.
V4 settlement action `TAKE_PAIR` accepts only two currency addresses and pays the
position manager's recorded sender. Ethereum V4 calldata cannot be substituted.

Unsigned mainnet simulations exercised minting, refunds, allowance revocation,
position increases, withdrawals, fee collection and native/TRC-20 creator reward
accrual and claims. The dated verification evidence records these checks.
Simulation and bytecode matching do not constitute an independent audit or
guarantee future protocol or wallet behavior.
