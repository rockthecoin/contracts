# Solana controller V1

Mainnet program: [`HyVdmUF12N9HpRfxQAxLskxqebjFah3nzirD28BGhLvo`](https://explorer.solana.com/address/HyVdmUF12N9HpRfxQAxLskxqebjFah3nzirD28BGhLvo).

The existing program is immutable: it has no upgrade authority. Its executable matches the published 110,224-byte ELF with SHA-256:

```text
f06f417780232e687d0c3c663a736e85e7431c2efbbe7089a2c4da994183a5dc
```

## Rebuild the existing executable

The source, `Cargo.toml` and `Cargo.lock` are preserved byte for byte in `contracts/solana-controller-v1/`. The original pins are Agave `cargo-build-sbf` 4.4.0, platform-tools v1.58, its Rust 1.95.0 toolchain, and SBF architecture `v0`.

On Linux x86-64, `scripts/install-solana-toolchain.sh ABSOLUTE_DIRECTORY` downloads those exact releases and checks their archive SHA-256 hashes before extraction. Add `ABSOLUTE_DIRECTORY/platform-tools/rust/bin` and `ABSOLUTE_DIRECTORY/solana-release/bin` to your `PATH`, then run:

```sh
bash scripts/rebuild-solana.sh
```

The script compares the newly built ELF with the saved executable. It leaves the published package unchanged. CI repeats this build. The compiler currently reports deprecated Solana SDK module warnings; changing the immutable source to suppress a warning would change the released package.

## Compare with mainnet

Install `requirements-test.txt` in a Python virtual environment, then run:

```sh
python scripts/verify-solana.py
```

This resolves the upgradeable loader's program-data account, compares the executable and zero padding, and reports the upgrade authority. The saved result is [solana-mainnet-check.json](verification/solana-mainnet-check.json).

## Registry verification

Reproducing and checking the binary is distinct from registering a verified build with the OtterSec/Solana verification service. The public repository supplies the exact sources and pinned build process needed for review. The registry's standard API requires upgrade-authority verification metadata; this program is already immutable. Solana's official documentation directs owners of such programs to `contact@osec.io` for its immutable-program process. This snapshot does not claim an OtterSec registry verification badge. No upgrade, redeployment or funded metadata transaction is performed by this repository's scripts.

See [Solana's verified-build documentation](https://solana.com/docs/programs/verified-builds). A verified-build label confirms source correspondence, not an independent audit or wallet-provider approval.
