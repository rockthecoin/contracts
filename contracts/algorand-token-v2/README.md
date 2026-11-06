# RockTheCoin Algorand token app V2

Immutable AVM 11 token / single-NFT controller. Deploy this program for new Algorand token services; use the unchanged collection and escrow V1 programs alongside it. Three operator apps are needed in total.

V2 keeps the V1 ABI, quote authorization domain and state layout. It fixes reserve reissuance at uint64's boundary when the optional lifetime cap is disabled. The informational cumulative issuance counter saturates at uint64's maximum while the circulating-supply cap still applies. A configured lifetime issuance cap remains enforced. All earlier V1 programs, reviews and verification stay available byte for byte; an existing registered app is never silently replaced.

Compiler pins: Python 3.12, PuyaPy 5.10.1, Algorand Python 4.0.0. Verify the frozen build with `node scripts/compile-algorand-token-v2.mjs --verify`. Further behavior changes require a new release. The app exposes no update or delete path.

`docs/algorand-suite.md` covers deployment, native asset restrictions, tests and Tinyman V2 integration. Smart ASA controlled transfers are not native ASA transfers and cannot be used on Tinyman. Deployment, service activation and network publication remain explicit operator actions.
