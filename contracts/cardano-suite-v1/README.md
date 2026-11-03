# cardano-suite-v1

Historical advanced native issuance, metadata, vesting and asset-lock validators. Use V2 for new creations.

Aiken **v1.1.24+bacbeb3**, Plutus **V3**, stdlib **v4.0.0**.

This is a frozen contract package. `artifacts/published.lock` pins the source and artifacts. New behavior requires a new version.

See [Cardano verification](../../docs/cardano-verification.md), [permissions](../../docs/permissions.md#native-cardano) and [mainnet references](../../docs/deployments.md#cardano).

Verify without modifying this package:

```sh
python3 scripts/verify-cardano.py
python3 scripts/rebuild-cardano.py
```

Run those commands from the repository root. Rebuilds use temporary directories. This package is Apache-2.0 licensed; see [LICENSE](LICENSE).
