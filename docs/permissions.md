# Fees, permissions and trust assumptions

## Creation and payment

An EVM factory creates an asset and transfers the authorized native-currency service fee in the same transaction. A failure reverts creation and payment together; blockchain gas may still be charged. The Solana creator bundles asset instructions and native SOL service payment into one transaction. The optional Solana controller does not collect the platform service fee itself.

The service calculates prices from a EUR base off chain and signs a short-lived native-currency quote. The quote binds the payer, chain ID, factory, asset configuration, recipient, exact fee, expiry and unique reference. EVM factory quotes expire within five minutes and cannot be reused after successful execution. Native network costs and external protocol costs are additional.

Factory addresses do not need to change when the off-chain EUR price changes. Changing the on-chain service recipient or quote authorization address requires an owner transaction. Existing assets retain their original code and creator-selected permissions.

## Platform controls

| Component | Platform owner can | Limits |
| --- | --- | --- |
| Basic, managed, advanced and collection factories | Pause new factory operations; change service recipient and quote signer; transfer factory ownership with acceptance | These settings do not transfer ownership of previously created tokens or collections |
| ServiceTools | Pause new tool operations; change recipient/signer; allow or disallow protocol targets | Execution also requires an authorized plan and the customer's transaction. Users must review the target, calldata, input amounts and allowances |
| Rewards hooks | Pause new registrations and reward accrual; rotate registration signer; transfer hook ownership | Pause leaves existing claims and swaps available. Pool fee ceilings and creator freeze decisions remain enforced |
| CREATE2 hook helper | Deploy supplied hook creation code from owner-approved transactions | The helper does not control tokens or existing pool positions |
| Solana controller V1 | No platform administrator or upgrade key | Its published program is immutable. Manager and beneficiary keys are supplied by the creator |

The EVM deployments in this snapshot use their published implementation runtime directly, without upgradeable proxies. Owner controls are meaningful trust assumptions: for example, liquidity routing depends on both authorized quotes and the protocol target allowlist. Read the exact wallet transaction before approving; a wallet connection alone grants no allowance.

## Creator controls

Basic ERC-20 tokens have a fixed initial supply and holder burning. They have no additional minting, transfer taxes, blocklist or pause administrator.

Configurable tokens can retain mint, pause, blocklist, tax, pool, limit, trading and delegated-role permissions when selected at creation. These capabilities depend on the contract version. Permanent maximum supply, feature availability, tax ceilings and mutability flags are enforced by token code. Lifetime issuance caps do not reopen after burning; outstanding-supply caps can. Token owners and delegated role holders must be considered when assessing control.

ERC-721 collections belong to their creator. Only their current owner can mint within the lifetime cap, transfer ownership or permanently close minting. Burning an NFT does not restore the lifetime mint allowance. Royalty declarations do not force every marketplace to pay royalties.

Vesting and position-lock contracts hold assets until their immutable schedules permit release. Release destinations are fixed beneficiaries. Anyone may trigger ordinary release where the contract allows it; that does not let the caller choose a different beneficiary. Do not deposit into a lock without checking its token, beneficiary and schedule.

Creator rewards are optional pool-level fees, separate from ERC-20 transfer taxes. Registration fixes a maximum rate and whether its rate or recipient may change. Pool creator ownership uses acceptance; the platform owner does not become the pool creator.

Solana tokens use SPL Token or Token-2022; NFT collections use Metaplex Core. These third-party programs have their own permissions and semantics. Controller V1 optionally enforces mint caps, permanent transfer-fee ceilings and token vesting. Its cap/fee managers can be handed over or permanently revoked. Revoked authorities and immutable settings cannot be restored by RockTheCoin.

## Check the current state

Ownership, recipients, signers, pause state and enabled target lists can change through the controls above. [Deployment evidence](verification/) is dated, not a continuously refreshed health guarantee. Re-run the read-only verification commands and inspect the explorer before relying on an address.

## Native TRON

The native TRON factory and ServiceTools owners can change the service receiving
wallet and quote signer, approve protocol targets and pause new service calls.
These powers do not change existing tokens' creators or their selected asset
permissions. V3 implementation addresses are fixed and initialization is locked.
The reward-hook owner can pause new registration and accrual; existing claims
remain available. Creator pool settings stay subject to their permanent caps.

Prices are configured in EUR and converted to a short-lived native TRX quote.
Creation, the selected configuration and the service payment share one
transaction. Failed calls roll back the service payment; network Energy and
Bandwidth costs can still apply. Approvals, liquidity deposits, distribution
and subsequent collection minting have their own reviewed actions.

## Native Cardano

Cardano native assets use a per-creation minting policy. Fixed supply and meme
presets close additional issuance; managed/custom assets can retain capped
minting, delegated minters, issuance pause and editable metadata. Issuance pause
does not stop native transfers. Ordinary native assets do not have ERC-20
allowances, issuer transfer taxes, account blocklists or transfer freezes.

Controller ownership uses nomination and acceptance. Permanent mint closure,
metadata freezing and ownership renunciation cannot be reversed by the platform.
Collection item metadata may be frozen individually; freezing the collection
also prevents subsequent item updates through its controller.

Vesting and asset locks hold native assets for a fixed beneficiary and schedule.
Surplus recovery requires the vesting beneficiary and cannot consume the vesting
principal or its ADA reserve. Operator reference scripts are reusable code copies,
not customer balances. Their publisher can reclaim the reference deposit by
spending the output, but cannot change the published code or customer permissions.

Service prices are converted from EUR to ADA for the reviewed transaction.
Creation and its tagged service payment share one transaction. Script-failure
collateral and Cardano network costs remain separate. Minswap deposit/withdrawal
orders are placed first and executed later by a batcher; placing an order is not
the same event as its execution. Order cancellation returns its locked value;
an already-paid service fee for placement is not automatically refunded.

## Native Sui

The shared Move library and customer asset packages permanently consume their
UpgradeCap at publication. The library has no platform owner, global pause,
service-recipient setting or quote signer. Creator controllers retain only the
selected capabilities; delegated roles and ownership changes follow each asset's
configuration. Native coin and Kiosk behavior differs from ERC-20/ERC-721.

Service prices are converted from EUR to SUI. The selected action and native
service transfer share one reviewed programmable transaction; failure rolls back
both, with network gas separate. Cetus liquidity interacts with the external
Cetus protocol, not a RockTheCoin-owned exchange. See the [Sui permission limits](sui-verification.md#permissions-and-limits).

## Native TON / Gram

The suite factory owner can change the fee recipient and quote public key,
pause new launches and nominate a successor. The nominee must accept. These
powers do not upgrade code or withdraw customer assets. Quotes bind exact
native amounts; future fee settings cannot change existing asset terms.

Creators retain only their selected mint, metadata, role and freeze controls.
Closing minting or metadata editing is permanent. Collection caps count lifetime
issuance. Vesting and locks retain a fixed beneficiary and protect unvested
principal and surplus. TON messages settle asynchronously; a failed step can
need recovery and can still spend network fees. See [TON contracts](ton-suite.md).
