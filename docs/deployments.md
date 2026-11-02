# Mainnet deployment snapshot

Snapshot: **2026-11-02**, source release [`v1.0.1`](https://github.com/rockthecoin/contracts/releases/tag/v1.0.1). Each address below was compared with its exact saved runtime. The Solana executable was also rebuilt byte for byte. All 31 listed EVM contracts also have matching source verified by Sourcify. These are dated checks; service configuration and owner state can change.

See [machine-readable addresses](../deployments.json), [EVM comparison evidence](verification/evm-mainnet-check.json), [Solana comparison evidence](verification/solana-mainnet-check.json), [Sourcify source verification](verification/sourcify-source-status.json) and [verification instructions](verification.md).

## Solana

Solana mainnet-beta · Network fees: **SOL**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Supply caps, fee ceilings & vesting · Controller V1 | [`solana-controller-v1`](../contracts/solana-controller-v1) | [`HyVdmUF12N9HpRfxQAxLskxqebjFah3nzirD28BGhLvo`](https://solscan.io/address/HyVdmUF12N9HpRfxQAxLskxqebjFah3nzirD28BGhLvo) |

## Ethereum

Chain ID: `1` · Network fees: **ETH**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Basic token & single NFT factory · V2 | [`factory-v2`](../contracts/RockTheCoinFactory.sol) | [`0x2586c07cbc863270bc5678ebcd581f85ed12f5bc`](https://etherscan.io/address/0x2586c07cbc863270bc5678ebcd581f85ed12f5bc) |
| Managed & taxable token factory · V3 | [`launch-v3`](../contracts/launch-v3) | [`0x175511fa79baec7bb54325aadc9b4686c5f55f07`](https://etherscan.io/address/0x175511fa79baec7bb54325aadc9b4686c5f55f07) |
| Advanced token factory · V6 | [`launch-v6`](../contracts/launch-v6) | [`0x92b8c811b0d9c21cf338315ea82adc8784c9c93e`](https://etherscan.io/address/0x92b8c811b0d9c21cf338315ea82adc8784c9c93e) |
| NFT collection factory · V1 | [`collections-v1`](../contracts/collections-v1) | [`0x21ab8137f8d413e2816d4e7be0acdae7acdefb62`](https://etherscan.io/address/0x21ab8137f8d413e2816d4e7be0acdae7acdefb62) |
| Distribution & liquidity · ServiceTools V1 | [`tools-v1`](../contracts/tools-v1) | [`0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681`](https://etherscan.io/address/0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681) |
| Creator rewards address helper | [`rewards-v1`](../contracts/rewards-v1) | [`0xbfa92f78b27caad872e889bfc14fe16d1435be7f`](https://etherscan.io/address/0xbfa92f78b27caad872e889bfc14fe16d1435be7f) |
| Uniswap V4 creator rewards hook | [`rewards-v1`](../contracts/rewards-v1) | [`0xc46ab1f7e306a098250dfa2210c911b902b46044`](https://etherscan.io/address/0xc46ab1f7e306a098250dfa2210c911b902b46044) |

## BNB Chain

Chain ID: `56` · Network fees: **BNB**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Basic token & single NFT factory · V2 | [`factory-v2`](../contracts/RockTheCoinFactory.sol) | [`0x2586c07cbc863270bc5678ebcd581f85ed12f5bc`](https://bscscan.com/address/0x2586c07cbc863270bc5678ebcd581f85ed12f5bc) |
| Advanced token factory · V6 | [`launch-v6`](../contracts/launch-v6) | [`0x21ab8137f8d413e2816d4e7be0acdae7acdefb62`](https://bscscan.com/address/0x21ab8137f8d413e2816d4e7be0acdae7acdefb62) |
| NFT collection factory · V1 | [`collections-v1`](../contracts/collections-v1) | [`0x619ba400fb76057b548b0a604c0c379cad4d3800`](https://bscscan.com/address/0x619ba400fb76057b548b0a604c0c379cad4d3800) |
| Distribution & liquidity · ServiceTools V1 | [`tools-v1`](../contracts/tools-v1) | [`0x175511fa79baec7bb54325aadc9b4686c5f55f07`](https://bscscan.com/address/0x175511fa79baec7bb54325aadc9b4686c5f55f07) |
| Creator rewards address helper | [`rewards-v1`](../contracts/rewards-v1) | [`0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681`](https://bscscan.com/address/0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681) |
| Uniswap V4 creator rewards hook | [`rewards-v1`](../contracts/rewards-v1) | [`0xf8f03be18b5243d66b69e94e3ff84f123482a044`](https://bscscan.com/address/0xf8f03be18b5243d66b69e94e3ff84f123482a044) |

## Base

Chain ID: `8453` · Network fees: **ETH**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Basic token & single NFT factory · V2 | [`factory-v2`](../contracts/RockTheCoinFactory.sol) | [`0x2586c07cbc863270bc5678ebcd581f85ed12f5bc`](https://basescan.org/address/0x2586c07cbc863270bc5678ebcd581f85ed12f5bc) |
| Advanced token factory · V7 | [`launch-v7`](../contracts/launch-v7) | [`0x21ab8137f8d413e2816d4e7be0acdae7acdefb62`](https://basescan.org/address/0x21ab8137f8d413e2816d4e7be0acdae7acdefb62) |
| NFT collection factory · V1 | [`collections-v1`](../contracts/collections-v1) | [`0x175511fa79baec7bb54325aadc9b4686c5f55f07`](https://basescan.org/address/0x175511fa79baec7bb54325aadc9b4686c5f55f07) |
| Distribution & liquidity · ServiceTools V1 | [`tools-v1`](../contracts/tools-v1) | [`0x619ba400fb76057b548b0a604c0c379cad4d3800`](https://basescan.org/address/0x619ba400fb76057b548b0a604c0c379cad4d3800) |
| Creator rewards address helper | [`rewards-v1`](../contracts/rewards-v1) | [`0xc7610117193d63ed7aec80fcc2195641ebf23fa9`](https://basescan.org/address/0xc7610117193d63ed7aec80fcc2195641ebf23fa9) |
| Uniswap V4 creator rewards hook | [`rewards-v2`](../contracts/rewards-v2) | [`0x8fc5bfa88e3a0eeac09784b1a3f1c88c9de1a044`](https://basescan.org/address/0x8fc5bfa88e3a0eeac09784b1a3f1c88c9de1a044) |

## Arbitrum One

Chain ID: `42161` · Network fees: **ETH**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Basic token & single NFT factory · V2 | [`factory-v2`](../contracts/RockTheCoinFactory.sol) | [`0x21ab8137f8d413e2816d4e7be0acdae7acdefb62`](https://arbiscan.io/address/0x21ab8137f8d413e2816d4e7be0acdae7acdefb62) |
| Advanced token factory · V7 | [`launch-v7`](../contracts/launch-v7) | [`0x175511fa79baec7bb54325aadc9b4686c5f55f07`](https://arbiscan.io/address/0x175511fa79baec7bb54325aadc9b4686c5f55f07) |
| NFT collection factory · V1 | [`collections-v1`](../contracts/collections-v1) | [`0x619ba400fb76057b548b0a604c0c379cad4d3800`](https://arbiscan.io/address/0x619ba400fb76057b548b0a604c0c379cad4d3800) |
| Distribution & liquidity · ServiceTools V1 | [`tools-v1`](../contracts/tools-v1) | [`0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681`](https://arbiscan.io/address/0x6ce5d5ffca3c1e1cff9e3ac9553318af0d91e681) |
| Creator rewards address helper | [`rewards-v1`](../contracts/rewards-v1) | [`0xc7610117193d63ed7aec80fcc2195641ebf23fa9`](https://arbiscan.io/address/0xc7610117193d63ed7aec80fcc2195641ebf23fa9) |
| Uniswap V4 creator rewards hook | [`rewards-v3`](../contracts/rewards-v3) | [`0x73c0d2412168f5ee55385b61d33f9b9a86292044`](https://arbiscan.io/address/0x73c0d2412168f5ee55385b61d33f9b9a86292044) |

## Polygon

Chain ID: `137` · Network fees: **POL**.

| Contract | Versioned source | Mainnet address |
| --- | --- | --- |
| Basic token & single NFT factory · V2 | [`factory-v2`](../contracts/RockTheCoinFactory.sol) | [`0x2586c07cbc863270bc5678ebcd581f85ed12f5bc`](https://polygonscan.com/address/0x2586c07cbc863270bc5678ebcd581f85ed12f5bc) |
| Advanced token factory · V7 | [`launch-v7`](../contracts/launch-v7) | [`0x21ab8137f8d413e2816d4e7be0acdae7acdefb62`](https://polygonscan.com/address/0x21ab8137f8d413e2816d4e7be0acdae7acdefb62) |
| NFT collection factory · V1 | [`collections-v1`](../contracts/collections-v1) | [`0x175511fa79baec7bb54325aadc9b4686c5f55f07`](https://polygonscan.com/address/0x175511fa79baec7bb54325aadc9b4686c5f55f07) |
| Distribution & liquidity · ServiceTools V1 | [`tools-v1`](../contracts/tools-v1) | [`0x619ba400fb76057b548b0a604c0c379cad4d3800`](https://polygonscan.com/address/0x619ba400fb76057b548b0a604c0c379cad4d3800) |
| Creator rewards address helper | [`rewards-v1`](../contracts/rewards-v1) | [`0xc7610117193d63ed7aec80fcc2195641ebf23fa9`](https://polygonscan.com/address/0xc7610117193d63ed7aec80fcc2195641ebf23fa9) |
| Uniswap V4 creator rewards hook | [`rewards-v3`](../contracts/rewards-v3) | [`0x78f33a7e9a061821fc5fbf35d203c7b0df622044`](https://polygonscan.com/address/0x78f33a7e9a061821fc5fbf35d203c7b0df622044) |
