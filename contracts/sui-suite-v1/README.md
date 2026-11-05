# Immutable Sui library V1

Seven native Move modules implement creator authority, configurable coins,
collections, Kiosk royalty rules, distribution, vesting and owned-object locks.

The library is published once and permanently gives up its UpgradeCap. It has
no platform owner, upgrade key, treasury, quote signer or platform pause.
Each creator publishes a distinct asset type and owns the permissions retained
in that asset's controller. Every creator package also removes its UpgradeCap.

`package/` contains the deployed seven-module source. `templates/coin/` is the
current configurable coin template. `templates/collection/` is the original
collection template, preserved for source compatibility. New NFT/collection
creation uses the separate [V2 template](../sui-creators-v2).

The exact compiler, framework, sources, module bytes and SHA-256 values are in
`artifacts/`. Preserve these files; behavior changes require a new version.
Builds and tests operate only on temporary copies.

See [Sui verification](../../docs/sui-verification.md), the
[deployment map](../../deployments.json), and
[dated mainnet checks](../../verification/sui-mainnet-2026-11-05.json).
