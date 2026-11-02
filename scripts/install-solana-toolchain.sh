#!/usr/bin/env bash
set -euo pipefail
rtc_tools_dir="${1:?Usage: install-solana-toolchain.sh ABSOLUTE_DIRECTORY}"
mkdir -p "$rtc_tools_dir"
cd "$rtc_tools_dir"
curl --fail --location --retry 3 --output agave.tar.bz2 https://github.com/anza-xyz/agave/releases/download/v4.3.2/solana-release-x86_64-unknown-linux-gnu.tar.bz2
curl --fail --location --retry 3 --output platform-tools.tar.bz2 https://github.com/anza-xyz/platform-tools/releases/download/v1.58/platform-tools-linux-x86_64.tar.bz2
echo '5c9599d7fa397375df69d58e8d4f550ee45463dd6d1ecad9e5a1f053ce8e0933  agave.tar.bz2' | sha256sum --check --strict
echo '7b82eb420b5aebd1e5590db0ae25c523eca06724d4238ae02139690535636c37  platform-tools.tar.bz2' | sha256sum --check --strict
tar -xjf agave.tar.bz2
mkdir -p platform-tools
tar -xjf platform-tools.tar.bz2 -C platform-tools
mkdir -p "$HOME/.cache/solana/v1.58"
ln -s "$rtc_tools_dir/platform-tools" "$HOME/.cache/solana/v1.58/platform-tools"
echo "Installed pinned binaries in $rtc_tools_dir"
