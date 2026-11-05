module rtc_suite::collection;

use std::string::String;
use rtc_suite::authority::{Self, Authority};
use rtc_suite::royalty;
use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
use sui::event;

const EInvalidCollection: u64 = 1;
const EMintClosed: u64 = 2;
const ESupplyCap: u64 = 3;
const EMetadataFrozen: u64 = 4;
const ERoyaltyFrozen: u64 = 5;
const EWrongPolicy: u64 = 6;
const EResumeFirst: u64 = 7;

public struct Collection<phantom T> has key, store {
    id: UID,
    authority: Authority,
    policy_cap: TransferPolicyCap<T>,
    policy_id: ID,
    name: String,
    symbol: String,
    description: String,
    image_url: String,
    metadata_uri: String,
    maximum_supply: u64,
    minted: u64,
    mintable: bool,
    burnable: bool,
    metadata_mutable: bool,
    paused: bool,
    royalty_mutable: bool,
    maximum_royalty_bps: u16,
}
/// No abilities: a mint authorization must be consumed in this transaction.
public struct MintTicket<phantom T> { collection: ID, serial: u64 }
public struct Created has copy, drop {
    id: ID, creator: address, owner: address, policy: ID, maximum_supply: u64,
    burnable: bool, metadata_mutable: bool, royalty_bps: u16,
    royalty_recipient: address, maximum_royalty_bps: u16, royalty_mutable: bool,
}

public fun new<T>(policy: &mut TransferPolicy<T>, policy_cap: TransferPolicyCap<T>,
    owner: address, delegates: vector<address>, delegate_masks: vector<u64>,
    name: String, symbol: String, description: String,
    image_url: String, metadata_uri: String, maximum_supply: u64,
    burnable: bool, metadata_mutable: bool, royalty_bps: u16,
    royalty_recipient: address, maximum_royalty_bps: u16,
    royalty_mutable: bool, ctx: &mut TxContext): Collection<T> {
    assert!(name.length() > 0 && name.length() <= 32 && symbol.length() > 0 &&
        symbol.length() <= 10 && description.length() <= 2000 && image_url.length() <= 500 &&
        metadata_uri.length() <= 600 && maximum_supply > 0 && maximum_supply <= 1000000 &&
        royalty_bps <= maximum_royalty_bps && maximum_royalty_bps <= 10000, EInvalidCollection);
    // Native policy checks bind this cap to the exact TransferPolicy object.
    royalty::set(policy, &policy_cap, royalty_bps, royalty_recipient);
    let policy_id = object::id(policy);
    let collection = Collection { id: object::new(ctx),
        authority: authority::with_roles(owner, delegates, delegate_masks),
        policy_cap, policy_id, name, symbol, description, image_url, metadata_uri,
        maximum_supply, minted: 0, mintable: true, burnable, metadata_mutable,
        paused: false, royalty_mutable, maximum_royalty_bps };
    event::emit(Created { id: object::id(&collection), creator: ctx.sender(), owner,
        policy: policy_id, maximum_supply, burnable, metadata_mutable, royalty_bps,
        royalty_recipient, maximum_royalty_bps, royalty_mutable });
    collection
}
public fun authorize_mint<T>(c: &mut Collection<T>, ctx: &TxContext): MintTicket<T> {
    authority::assert_role(&c.authority, ctx.sender(), 1);
    assert!(c.mintable && !c.paused, EMintClosed);
    assert!(c.minted < c.maximum_supply, ESupplyCap);
    c.minted = c.minted + 1;
    MintTicket { collection: object::id(c), serial: c.minted }
}
public fun consume_ticket<T>(ticket: MintTicket<T>): (ID, u64) {
    let MintTicket { collection, serial } = ticket; (collection, serial)
}
public fun assert_metadata<T>(c: &Collection<T>, ctx: &TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 2);
    assert!(c.metadata_mutable, EMetadataFrozen);
}
public fun update_metadata<T>(c: &mut Collection<T>, name: String,
    description: String, image_url: String, metadata_uri: String, ctx: &TxContext) {
    assert_metadata(c, ctx);
    assert!(name.length() > 0 && name.length() <= 32 && description.length() <= 2000 &&
        image_url.length() <= 500 && metadata_uri.length() <= 600, EInvalidCollection);
    c.name = name; c.description = description; c.image_url = image_url; c.metadata_uri = metadata_uri;
}
public fun freeze_metadata<T>(c: &mut Collection<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender()); c.metadata_mutable = false;
}
public fun set_royalty<T>(c: &mut Collection<T>, policy: &mut TransferPolicy<T>,
    bps: u16, recipient: address, ctx: &TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 8);
    assert!(c.royalty_mutable && bps <= c.maximum_royalty_bps, ERoyaltyFrozen);
    assert!(object::id(policy) == c.policy_id, EWrongPolicy);
    royalty::set(policy, &c.policy_cap, bps, recipient);
}
public fun freeze_royalty<T>(c: &mut Collection<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender()); c.royalty_mutable = false;
}
public fun set_paused<T>(c: &mut Collection<T>, paused: bool, ctx: &TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 4); c.paused = paused;
}
public fun revoke_mint<T>(c: &mut Collection<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender()); c.mintable = false;
}
public fun set_role<T>(c: &mut Collection<T>, recipient: address, mask: u64, ctx: &TxContext) {
    authority::set_role(&mut c.authority, ctx.sender(), recipient, mask);
}
public fun nominate_owner<T>(c: &mut Collection<T>, recipient: address, ctx: &TxContext) {
    authority::nominate(&mut c.authority, ctx.sender(), recipient);
}
public fun cancel_nomination<T>(c: &mut Collection<T>, ctx: &TxContext) {
    authority::cancel_nomination(&mut c.authority, ctx.sender());
}
public fun accept_owner<T>(c: &mut Collection<T>, ctx: &TxContext) {
    authority::accept(&mut c.authority, ctx.sender());
}
public fun renounce_owner<T>(c: &mut Collection<T>, ctx: &TxContext) {
    assert!(!c.paused, EResumeFirst);
    authority::renounce(&mut c.authority, ctx.sender());
    c.mintable = false; c.metadata_mutable = false; c.royalty_mutable = false;
}
public fun owner<T>(c: &Collection<T>): address { authority::owner(&c.authority) }
public fun minted<T>(c: &Collection<T>): u64 { c.minted }
public fun burnable<T>(c: &Collection<T>): bool { c.burnable }
public fun metadata_mutable<T>(c: &Collection<T>): bool { c.metadata_mutable }
