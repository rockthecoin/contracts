#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo-build-sbf --manifest-path contracts/solana-controller-v1/Cargo.toml --arch v0 --tools-version v1.58 --skip-tools-install --no-rustup-override -- --locked
python3 - <<'PY'
import hashlib,pathlib
folder=pathlib.Path('contracts/solana-controller-v1')
rebuilt=(folder/'target/deploy/rockthecoin_controller.so').read_bytes()
published=(folder/'artifacts/rockthecoin_controller.so').read_bytes()
assert rebuilt==published,'Rebuilt program differs from published executable'
print('Exact controller rebuild:',hashlib.sha256(rebuilt).hexdigest())
PY
