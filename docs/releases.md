# Version notes

Package versions are independent. A repository release groups a source snapshot; it does not make every network use the highest version.

- **Basic factory V2:** short-lived EUR-denominated quote authorizations settled in native currency; basic token and single-NFT creation.
- **Launch V3:** earlier managed and taxable ERC-20 implementation, retained for existing addresses and assets.
- **Launch V4 and V5:** historical advanced implementations. Kept for inspection and compatibility, not presented as recommended new deployments.
- **Launch V6:** enforces destination wallet limits across received transfer and tax amounts, and prevents renouncing token ownership while paused. Used by Ethereum and BNB in this snapshot.
- **Launch V7:** retains the V6 behavior and validates vesting deposits by the received balance delta. A donation to a predictable escrow address cannot block creation solely by increasing its starting balance. Used by Base, Arbitrum and Polygon in this snapshot.
- **Collections V1:** creator-owned ERC-721 collections with a lifetime supply cap, bounded batches, two-step ownership and permanent mint closure.
- **ServiceTools V1:** atomic native/token distributions and authorized liquidity execution; protocol allowlist, protected starting balances and temporary allowance cleanup.
- **Rewards V1:** optional bounded Uniswap V4 creator rewards and CREATE2 helper. Used by Ethereum and BNB in this snapshot.
- **Rewards V2:** rejects underfunded incoming fee receipts so transfer-tax currencies cannot create unbacked reward claims. Used by Base in this snapshot.
- **Rewards V3:** adds an outgoing balance floor so sender surcharges cannot consume backing reserved for other recipients. Used by Polygon and Arbitrum in this snapshot.
- **Solana controller V1:** immutable mint caps, fee ceilings and vesting. The published ELF has been rebuilt and compared with the existing mainnet program.

Earlier versions remain separate packages. Known changes in a later version must not be interpreted as present in an earlier deployment. Local tests and source publication do not replace independent review. See [SECURITY.md](../SECURITY.md) for private reporting.

## v1.1.0 — Native TRON

Adds the native TRON V1/V2/V3 source packages, saved compiler inputs and artifacts, the five mainnet deployment records, compiler reproduction checks and dated unsigned TVM/SunSwap simulation evidence. Existing EVM and Solana contract bytes are unchanged. TRON V3 uses fixed clones for creation and locks; distribution and creator rewards retain V1 contracts.
