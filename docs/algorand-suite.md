# Algorand mainnet contracts

RockTheCoin uses three immutable AVM applications on Algorand mainnet. ALGO pays
the quoted service fee, network fees and required minimum-balance deposits.

| Service | Program | Application ID |
| --- | --- | --- |
| Tokens and single NFTs | Token V2 | [3763966036](https://lora.algokit.io/mainnet/application/3763966036) |
| NFT collections | Collections V1 | [3763966705](https://lora.algokit.io/mainnet/application/3763966705) |
| Vesting and asset locks | Escrows V1 | [3763967109](https://lora.algokit.io/mainnet/application/3763967109) |

The recorded deployment owner and receiving wallet is
`4XW5PAYENTSP2MRGOTTPBL4V46OHSQMNWSAUZFRPCRA6OXQSVULY2QKQNI`.
See the [deployment map](../deployments.json) for original transaction IDs,
rounds, quote signer, source bundles and artifact locations.

## Assets and permissions

- Native ASAs use Algorand's immutable maximum supply. Optional reserve issuance,
  burns, freezes, clawbacks, roles and ARC19 metadata are configured by the creator.
  Issuance and creation fees succeed together in one atomic transaction group.
- Smart ASAs use default-frozen holdings and controller transfers. Optional taxes,
  split recipients, exemptions, limits, trading controls, allowances and current
  voting weight apply through the immutable controller. These assets cannot use
  ordinary native ASA transfers or Tinyman pools.
- Native NFTs and collections support caps, delegated minting, metadata controls,
  two-step ownership and irreversible mint closure. Collection royalties are
  advisory details for compatible marketplaces, rather than universally enforced
  native-transfer royalties. Minted items first enter the minter's wallet;
  recipients opt in before subsequent transfers.
- Vesting and locks use a separate LogicSig account per position, rekeyed only to
  the immutable escrow app in the same atomic group. Releases always go to the
  recorded beneficiary. The operator cannot withdraw customer escrow assets.
  Assets with freeze or clawback authority are rejected for escrow backing.
- The operator can change its receiving wallet and quote signer, pause new
  creations and nominate a successor owner. It cannot update/delete these programs
  or acquire creator-controlled token, collection or escrow permissions.

Tinyman V2's existing mainnet validator is **1002541853**. RockTheCoin does not
deploy its own AMM. Pool creation, deposits, withdrawals and LP token locks are
supported for compatible native ASAs. Pool bootstrap and first deposit require
separate reviews because bootstrap creates the LP asset ID. LP fees compound in
pool reserves; this integration does not claim Uniswap V4 hooks or concentrated
liquidity positions. The validator is documented by [Tinyman](https://docs.tinyman.org/contracts).

## Versions

`algorand-suite-v1` retains all three original V1 programs and the escrow LogicSig
template. Current issuance uses the separate `algorand-token-v2` package alongside
unchanged collection and escrow V1 programs. Token V2 preserves the V1 state ABI
and quote domain, and fixes reserve reissuance at uint64's lifetime-counter
boundary when the optional lifetime cap is disabled. The informational counter
saturates while the circulating-supply cap remains enforced. A configured
lifetime cap stays enforced. Earlier programs and approvals retain their exact
bytes; publication does not upgrade any deployed asset or program.

## Reproduction and verification

Use Python 3.12 and a virtual environment:

```sh
python3.12 -m venv .toolchains/algorand
.toolchains/algorand/bin/pip install -r requirements-algorand.txt
python3 scripts/verify-algorand.py
.toolchains/algorand/bin/python scripts/rebuild-algorand.py
python3 scripts/verify-algorand-chain.py
node scripts/compile-algorand-escrow.mjs --verify
```

PuyaPy **5.10.1** and Algorand Python **4.0.0** are pinned. Rebuilds use temporary
directories and compare the complete AVM programs and ARC56 ABI/schema with the
published artifacts. Offline checks also validate every frozen file, source
bundle, program hash, page budget and escrow template. The final command uses
the public Algod TEAL assembler to compare the existing LogicSig template; it
does not sign or broadcast a transaction. The chain verifier checks mainnet
identity, exact program bytes, schema, pages, version, owner, recipient, signer,
unpaused state and original creation IDs in canonical blocks.

## Recorded checks

- [Mainnet programs, owner configuration and canonical deployment proofs](../verification/algorand-readiness-2026-11-06.json)
- [Unsigned checks against the three deployed applications](../verification/algorand-customer-2026-11-06.json)
- [Unsigned Tinyman pool, deposit and withdrawal checks](../verification/algorand-tinyman-2026-11-06.json)

Customer simulations cover five token presets, single NFTs, collections,
distribution, ALGO vesting and asset locks with the actual service quote signer
and fee settings. Public account balances are unsigned simulation fixtures. No
wallet private key, funded wallet signature or broadcast is used. These are
project-maintained checks; source matching and successful simulations do not
constitute an independent audit or prove an absence of vulnerabilities.
