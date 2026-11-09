# TON suite V2 review notes — 2026-11-09

Scope: the six immutable Tolk contracts and their frozen source/artifact locks.
V1 remains available for historical comparison; existing asset code is not
replaced by publication of V2.

V2 addresses these contract behaviors:

- Escrow payment recovery preserves principal and donated surplus for the fixed
  beneficiary instead of treating the full balance as retry credit.
- Collection minting binds the expected item index. A completed request cannot
  mint another index on replay.
- Item initialization retries acknowledge the original mint without resetting
  metadata that was subsequently edited or frozen.
- NFT burn state survives a delayed fee bounce; payment recovery cannot revive
  the burned NFT.
- Token and collection controls reject changes before authenticated launch.

Reproduction checks the exact Tolk 1.5.0 output against saved artifacts. The
public TVM tests exercise creation/payment, replay, signature/payer/expiry
binding, owner configuration, collection index binding and fixed-beneficiary
vesting. Mainnet evidence separately checks the deployed factory, original
initialization and parent/child message link.

TON has no cross-contract global rollback. Network and storage costs remain
separate, non-native escrow funding needs its own transaction, and marketplace
royalties are advisory. Owner and creator keys can exercise retained powers.
Verification does not establish a market, liquidity or token value.

These are maintainer review notes and executable checks, not an independent
security audit or a guarantee that the contracts have no defects.
