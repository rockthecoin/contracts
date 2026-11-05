# Version notes

Package versions are independent. A repository release groups a source snapshot; it does not make every network use the highest version.

- **Basic factory V2:** short-lived EUR-denominated quote authorizations settled in native currency; basic token and single-NFT creation.
- **Launch V3:** earlier managed and taxable ERC-20 implementation, retained for existing addresses and assets.
- **Launch V4 and V5:** historical advanced implementations. Kept for inspection and compatibility, not presented as recommended new deployments.
- **Launch V6:** enforces destination wallet limits across received transfer and tax amounts, and prevents renouncing token ownership while paused. Used by Ethereum and BNB in this snapshot.
- **Launch V7:** retains the V6 behavior and validates vesting deposits by the received balance delta. A donation to a predictable escrow address cannot block creation solely by increasing its starting balance. Used by Base, Arbitrum and Polygon in this snapshot.
- **Launch V8:** retains V7 token controls and protects locked principal and donated surplus against tokens that debit an additional sender fee during either vesting payout. Uses quote-domain version 8. Used by Avalanche and Optimism in this snapshot; earlier deployments keep their original code.
- **Collections V1:** creator-owned ERC-721 collections with a lifetime supply cap, bounded batches, two-step ownership and permanent mint closure.
- **ServiceTools V1:** atomic native/token distributions and authorized liquidity execution; protocol allowlist, protected starting balances and temporary allowance cleanup.
- **Rewards V1:** optional bounded Uniswap V4 creator rewards and CREATE2 helper. Used by Ethereum and BNB in this snapshot.
- **Rewards V2:** rejects underfunded incoming fee receipts so transfer-tax currencies cannot create unbacked reward claims. Used by Base in this snapshot.
- **Rewards V3:** adds an outgoing balance floor so sender surcharges cannot consume backing reserved for other recipients. Used by Polygon, Arbitrum, Avalanche and Optimism in this snapshot.
- **Solana controller V1:** immutable mint caps, fee ceilings and vesting. The published ELF has been rebuilt and compared with the existing mainnet program.

Earlier versions remain separate packages. Known changes in a later version must not be interpreted as present in an earlier deployment. Local tests and source publication do not replace independent review. See [SECURITY.md](../SECURITY.md) for private reporting.

## v1.1.0 — Native TRON

Adds the native TRON V1/V2/V3 source packages, saved compiler inputs and artifacts, the five mainnet deployment records, compiler reproduction checks and dated unsigned TVM/SunSwap simulation evidence. Existing EVM and Solana contract bytes are unchanged. TRON V3 uses fixed clones for creation and locks; distribution and creator rewards retain V1 contracts.

## v1.2.0 — Native Cardano

Adds the original Cardano V1 creation policy, historical suite V1 and current
suite V2, Aiken sources/tests, blueprints, compiled scripts, compiler pins and
four confirmed V2 mainnet reference outputs. Includes offline hash checks,
reproducible Aiken builds, read-only mainnet reference verification and dated
unsigned customer evaluation evidence. Existing EVM, Solana and TRON package
bytes are unchanged. Each customer's issuance policy remains separately
parameterized; reference publication does not upgrade existing assets.

## v1.3.0 — Native Sui

Adds the immutable seven-module Sui library V1, current coin template, historical
NFT template and current NFT/collection template V2. Includes original Move
sources and tests, source/artifact locks, checksum-pinned compiler installation,
byte-for-byte reproduction and 35 native Move tests. The mainnet record verifies
the publication sender, checkpoint, all seven stored modules and removal of the
UpgradeCap in the publication transaction. Twelve unsigned mainnet customer
simulations cover all token presets, single NFTs, collections, distribution and
vesting. No funded transaction was signed or broadcast for these checks. Earlier
EVM, Solana, TRON and Cardano contract bytes are unchanged.

## v1.4.0 — Avalanche and vesting V8

Adds the frozen EVM Builder V8 Solidity sources, compiler input, ABIs and bytecode,
and the six verified Avalanche C-Chain mainnet deployments. V8 protects vesting
principal and surplus against excessive sender debits and keeps accepted older
quote versions separate. Standalone tests exercise both payout paths, rollback,
recipient taxes, returned donations, reentrancy and the V8 quote domain on chain
43114. Eight unsigned mainnet creation/distribution checks and three native-AVAX
liquidity plans passed. All five protocol targets were approved at a finalized
block. Earlier package source and artifact bytes are unchanged.

## v1.5.0 — Optimism mainnet

Adds the six verified OP Mainnet deployments, finalized approval of all five
liquidity/reward targets and dated runtime, source and customer verification.
Optimism uses the unchanged Builder V8 and creator-rewards hook V3. Standalone
checks cover OP chain/domain binding, atomic ETH service payments, vesting
backing and callbacks, and the Osaka transaction gas ceiling. Existing frozen
contract sources, compiler inputs and artifact bytes are unchanged.
