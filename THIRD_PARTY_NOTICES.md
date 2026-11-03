# Third-party sources

Saved Solidity standard JSON compiler inputs include the exact dependency sources used for each release. Preserve their SPDX identifiers and upstream notices when reusing them. All embedded Solidity sources in this snapshot declare MIT.

| Dependency | Source | License |
| --- | --- | --- |
| OpenZeppelin Contracts 5.6.1 | https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1 | MIT, copyright OpenZeppelin |
| Uniswap V4 core interfaces and types, 1.0.2 | https://github.com/Uniswap/v4-core | MIT for the files embedded here; other upstream files may have different licenses |

The repository MIT license applies to RockTheCoin's own contributions. It does not replace third-party licenses. The Solana `Cargo.lock` and npm lockfile identify additional build and test dependencies; those dependencies retain their own licenses and are downloaded by the respective package managers.

The Cardano packages declare **Apache-2.0**, as recorded in their original
`aiken.toml` files and package `LICENSE` files. This repository's root MIT license
does not replace those package licenses. Aiken stdlib v4.0.0 is fetched through
the original Aiken lockfiles and retains its upstream license and notices.
