# RockTheCoin Algorand suite V1

Three immutable AVM 11 apps: native / Smart ASA token controls, native ASA NFT collections, and separate-account vesting / asset locks. The per-lock account template uses AVM 8 LogicSig and is rekeyed only to the immutable escrow app in the same atomic group.

Deployment instructions, feature boundaries and verification are documented in `docs/algorand-suite.md`. Operator deployment uses the exact programs and ABI in `artifacts/suite.json` through Pera. No EVM factory or new Tinyman deployment is required.

Compiler: PuyaPy 5.10.1, Algorand Python 4.0.0, Python 3.12. Frozen bytecode must be reproduced using `scripts/compile-algorand.mjs --verify`; normal compilation is blocked once `published.lock` exists. Further behavior changes require a new release. Accepted approvals and earlier Algorand V1 native creations keep their original bytes and verification paths.
