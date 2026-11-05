# Sui NFT and collection creator V2

This template uses the unchanged [Sui library V1](../sui-suite-v1). Each creation
publishes a distinct immutable asset package. No second shared operator package
is required.

V2 supports optional initial NFT minting in the creation transaction and a
holder-input function for permanently freezing an owned NFT's metadata.
Collections retain lifetime mint caps, delegated roles, two-step ownership,
optional holder burns and configurable Kiosk royalty rules with a permanent
rate ceiling. Editing an owned NFT requires both metadata permission and the
holder's owned-object input. Direct transfers do not enforce royalties.

Sources, native tests, compiler pins and frozen artifacts are included. Template
constants are placeholders, not deployable customer settings. Parameterize all
settings, keep a unique typed constant pool and remap constant loads before
publication. The package's UpgradeCap must be consumed in the same transaction.
Initial minting requires mint permission for the signing account.

See [Sui verification](../../docs/sui-verification.md) for reproducible builds and
native tests. These project-maintained checks are not an independent audit.
