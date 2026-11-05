module rtc_suite::coin_control;

use std::string::String;
use rtc_suite::authority::{Self, Authority};
use sui::coin::{Self, Coin, CoinMetadata, TreasuryCap, DenyCapV2};
use sui::deny_list::DenyList;
use sui::event;
use sui::vec_set::{Self, VecSet};

const EInvalidConfiguration: u64 = 1;
const EFeatureRemoved: u64 = 2;
const ESupplyCap: u64 = 3;
const EInvalidAmount: u64 = 4;
const EWrongMetadata: u64 = 5;
const EClearRestrictionsFirst: u64 = 6;

/// One controller per native coin type. Its capabilities are never borrowable
/// outside this module, and the platform has no administrator over this object.
public struct Control<phantom T> has key, store {
    id: UID,
    authority: Authority,
    treasury: TreasuryCap<T>,
    metadata_id: ID,
    metadata_uri: String,
    deny_cap: Option<DenyCapV2<T>>,
    maximum_supply: u64,
    lifetime_cap: bool,
    minted: u64,
    mintable: bool,
    burnable: bool,
    metadata_mutable: bool,
    pause_allowed: bool,
    blocklist_allowed: bool,
    paused: bool,
    denied: VecSet<address>,
}
public struct Created has copy, drop {
    id: ID, creator: address, owner: address, metadata: ID, initial_supply: u64,
    maximum_supply: u64, lifetime_cap: bool, mintable: bool, burnable: bool,
    metadata_mutable: bool, pause_allowed: bool, blocklist_allowed: bool,
    metadata_uri: String,
}
public struct SupplyChanged has copy, drop { id: ID, minted: bool, amount: u64, supply: u64 }

/// Called by the new coin's one-time initializer. No type can obtain a second
/// TreasuryCap; the entire configuration belongs to its publishing creator.
#[allow(lint(share_owned))]
public fun new<T>(mut treasury: TreasuryCap<T>, metadata: CoinMetadata<T>,
    deny_cap: Option<DenyCapV2<T>>, owner: address, delegates: vector<address>,
    delegate_masks: vector<u64>, initial_supply: u64,
    maximum_supply: u64, lifetime_cap: bool, mintable: bool, burnable: bool,
    metadata_mutable: bool, pause_allowed: bool, blocklist_allowed: bool,
    metadata_uri: String, ctx: &mut TxContext): (Control<T>, Coin<T>) {
    assert!(coin::total_supply(&treasury) == 0 && initial_supply > 0 &&
        maximum_supply >= initial_supply &&
        (deny_cap.is_some() || (!pause_allowed && !blocklist_allowed)), EInvalidConfiguration);
    assert!(owner != @0x0 || (!mintable && !metadata_mutable && !pause_allowed &&
        !blocklist_allowed && delegates.is_empty() && delegate_masks.is_empty()), EInvalidConfiguration);
    let funds = coin::mint(&mut treasury, initial_supply, ctx);
    let metadata_id = object::id(&metadata);
    if (metadata_mutable) transfer::public_share_object(metadata)
    else transfer::public_freeze_object(metadata);
    let authority = if (owner == @0x0) authority::renounced()
        else authority::with_roles(owner, delegates, delegate_masks);
    let c = Control { id: object::new(ctx), authority, treasury,
        metadata_id, metadata_uri, deny_cap, maximum_supply, lifetime_cap,
        minted: initial_supply, mintable, burnable, metadata_mutable,
        pause_allowed, blocklist_allowed, paused: false, denied: vec_set::empty() };
    event::emit(Created { id: object::id(&c), creator: ctx.sender(), owner,
        metadata: metadata_id, initial_supply, maximum_supply, lifetime_cap,
        mintable, burnable, metadata_mutable, pause_allowed, blocklist_allowed, metadata_uri });
    (c, funds)
}
public fun mint<T>(c: &mut Control<T>, amount: u64, recipient: address, ctx: &mut TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 1);
    assert!(c.mintable && !c.paused, EFeatureRemoved);
    assert!(amount > 0 && recipient != @0x0, EInvalidAmount);
    let used = if (c.lifetime_cap) c.minted else coin::total_supply(&c.treasury);
    assert!((used as u128) + (amount as u128) <= (c.maximum_supply as u128), ESupplyCap);
    // The lifetime counter is only needed for a lifetime cap. A current-supply
    // cap may legitimately mint more than u64 cumulatively across later burns.
    if (c.lifetime_cap) c.minted = c.minted + amount;
    let funds = coin::mint(&mut c.treasury, amount, ctx);
    event::emit(SupplyChanged { id: object::id(c), minted: true, amount,
        supply: coin::total_supply(&c.treasury) });
    transfer::public_transfer(funds, recipient);
}
public fun burn<T>(c: &mut Control<T>, funds: Coin<T>) {
    assert!(c.burnable, EFeatureRemoved);
    let amount = coin::burn(&mut c.treasury, funds);
    event::emit(SupplyChanged { id: object::id(c), minted: false, amount,
        supply: coin::total_supply(&c.treasury) });
}
public fun revoke_mint<T>(c: &mut Control<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender()); c.mintable = false;
}
public fun freeze_metadata<T>(c: &mut Control<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender()); c.metadata_mutable = false;
}
public fun update_metadata<T>(c: &mut Control<T>, metadata: &mut CoinMetadata<T>,
    name: String, symbol: std::ascii::String, description: String, icon_url: std::ascii::String,
    metadata_uri: String, ctx: &TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 2);
    assert!(c.metadata_mutable, EFeatureRemoved);
    assert!(object::id(metadata) == c.metadata_id, EWrongMetadata);
    assert!(name.length() > 0 && name.length() <= 32 && symbol.length() > 0 && symbol.length() <= 10 && description.length() <= 2000 &&
        icon_url.length() <= 500 && metadata_uri.length() <= 600, EInvalidConfiguration);
    coin::update_name(&c.treasury, metadata, name);
    coin::update_symbol(&c.treasury, metadata, symbol);
    coin::update_description(&c.treasury, metadata, description);
    coin::update_icon_url(&c.treasury, metadata, icon_url);
    c.metadata_uri = metadata_uri;
}
public fun set_paused<T>(c: &mut Control<T>, deny_list: &mut DenyList,
    paused: bool, ctx: &mut TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 4);
    assert!(c.pause_allowed && c.deny_cap.is_some(), EFeatureRemoved);
    if (paused) coin::deny_list_v2_enable_global_pause(deny_list, c.deny_cap.borrow_mut(), ctx)
    else coin::deny_list_v2_disable_global_pause(deny_list, c.deny_cap.borrow_mut(), ctx);
    c.paused = paused;
}
public fun set_blocked<T>(c: &mut Control<T>, deny_list: &mut DenyList,
    account: address, blocked: bool, ctx: &mut TxContext) {
    authority::assert_role(&c.authority, ctx.sender(), 8);
    assert!(c.blocklist_allowed && c.deny_cap.is_some(), EFeatureRemoved);
    assert!(account != @0x0, EInvalidConfiguration);
    if (blocked) {
        coin::deny_list_v2_add(deny_list, c.deny_cap.borrow_mut(), account, ctx);
        if (!c.denied.contains(&account)) c.denied.insert(account);
    } else {
        coin::deny_list_v2_remove(deny_list, c.deny_cap.borrow_mut(), account, ctx);
        if (c.denied.contains(&account)) c.denied.remove(&account);
    };
}
public fun revoke_regulation<T>(c: &mut Control<T>, ctx: &TxContext) {
    authority::assert_owner(&c.authority, ctx.sender());
    assert!(!c.paused && c.denied.is_empty(), EClearRestrictionsFirst);
    c.pause_allowed = false; c.blocklist_allowed = false;
}
public fun set_role<T>(c: &mut Control<T>, recipient: address, mask: u64, ctx: &TxContext) {
    authority::set_role(&mut c.authority, ctx.sender(), recipient, mask);
}
public fun nominate_owner<T>(c: &mut Control<T>, recipient: address, ctx: &TxContext) {
    authority::nominate(&mut c.authority, ctx.sender(), recipient);
}
public fun cancel_nomination<T>(c: &mut Control<T>, ctx: &TxContext) {
    authority::cancel_nomination(&mut c.authority, ctx.sender());
}
public fun accept_owner<T>(c: &mut Control<T>, ctx: &TxContext) {
    authority::accept(&mut c.authority, ctx.sender());
}
public fun renounce_owner<T>(c: &mut Control<T>, ctx: &TxContext) {
    assert!(!c.paused && c.denied.is_empty(), EClearRestrictionsFirst);
    authority::renounce(&mut c.authority, ctx.sender());
    c.mintable = false; c.metadata_mutable = false;
    c.pause_allowed = false; c.blocklist_allowed = false;
}
public fun owner<T>(c: &Control<T>): address { authority::owner(&c.authority) }
public fun supply<T>(c: &Control<T>): u64 { coin::total_supply(&c.treasury) }
public fun maximum_supply<T>(c: &Control<T>): u64 { c.maximum_supply }
public fun mintable<T>(c: &Control<T>): bool { c.mintable }
public fun metadata_mutable<T>(c: &Control<T>): bool { c.metadata_mutable }
