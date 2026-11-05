module rtc_suite::object_lock;

use sui::clock::{Self, Clock};
use sui::event;

const EInvalidLock: u64 = 1;
const EStillLocked: u64 = 2;
const EAlreadyReleased: u64 = 3;

/// Accepts native NFTs and compatible DEX position NFTs without a DEX custody key.
public struct Lock<T: key + store> has key {
    id: UID, beneficiary: address, unlock_ms: u64, asset: Option<T>,
}
public struct Created has copy, drop {
    id: ID, creator: address, beneficiary: address, asset: ID, unlock_ms: u64,
}
public struct Released has copy, drop { id: ID, beneficiary: address, asset: ID }

public fun create<T: key + store>(asset: T, beneficiary: address, unlock_ms: u64,
    clock: &Clock, ctx: &mut TxContext): ID {
    assert!(beneficiary != @0x0 && unlock_ms > clock::timestamp_ms(clock), EInvalidLock);
    let asset_id = object::id(&asset);
    let lock = Lock { id: object::new(ctx), beneficiary, unlock_ms, asset: option::some(asset) };
    let id = object::id(&lock);
    event::emit(Created { id, creator: ctx.sender(), beneficiary, asset: asset_id, unlock_ms });
    transfer::share_object(lock); id
}
public fun release<T: key + store>(lock: &mut Lock<T>, clock: &Clock) {
    assert!(clock::timestamp_ms(clock) >= lock.unlock_ms, EStillLocked);
    assert!(lock.asset.is_some(), EAlreadyReleased);
    let asset = lock.asset.extract();
    event::emit(Released { id: object::id(lock), beneficiary: lock.beneficiary,
        asset: object::id(&asset) });
    transfer::public_transfer(asset, lock.beneficiary);
}
public fun beneficiary<T: key + store>(lock: &Lock<T>): address { lock.beneficiary }
