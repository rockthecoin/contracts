module rtc_suite::vesting;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::clock::{Self, Clock};
use sui::event;

const EInvalidSchedule: u64 = 1;
const ENothingVested: u64 = 2;
const ENothingExtra: u64 = 3;

public struct Vesting<phantom T> has key {
    id: UID,
    beneficiary: address,
    principal: u64,
    released: u64,
    start_ms: u64,
    cliff_ms: u64,
    end_ms: u64,
    funds: Balance<T>,
}
public struct Created has copy, drop {
    id: ID, creator: address, beneficiary: address,
    amount: u64, start_ms: u64, cliff_ms: u64, end_ms: u64,
}
public struct Released has copy, drop { id: ID, beneficiary: address, amount: u64 }

public fun create<T>(funds: Coin<T>, beneficiary: address, start_ms: u64,
    cliff_ms: u64, end_ms: u64, ctx: &mut TxContext): ID {
    let principal = coin::value(&funds);
    assert!(beneficiary != @0x0 && principal > 0 && start_ms < end_ms &&
        cliff_ms >= start_ms && cliff_ms <= end_ms, EInvalidSchedule);
    let v = Vesting { id: object::new(ctx), beneficiary, principal, released: 0,
        start_ms, cliff_ms, end_ms, funds: coin::into_balance(funds) };
    let id = object::id(&v);
    event::emit(Created { id, creator: ctx.sender(), beneficiary, amount: principal,
        start_ms, cliff_ms, end_ms });
    transfer::share_object(v); id
}

public fun vested<T>(v: &Vesting<T>, now_ms: u64): u64 {
    if (now_ms < v.cliff_ms || now_ms <= v.start_ms) 0
    else if (now_ms >= v.end_ms) v.principal
    else (((v.principal as u128) * ((now_ms - v.start_ms) as u128)) /
        ((v.end_ms - v.start_ms) as u128)) as u64
}
/// Anyone may trigger a release. The destination is permanently fixed.
public fun release<T>(v: &mut Vesting<T>, clock: &Clock, ctx: &mut TxContext) {
    let amount = vested(v, clock::timestamp_ms(clock)) - v.released;
    assert!(amount > 0, ENothingVested);
    v.released = v.released + amount;
    let payment = coin::from_balance(balance::split(&mut v.funds, amount), ctx);
    event::emit(Released { id: object::id(v), beneficiary: v.beneficiary, amount });
    transfer::public_transfer(payment, v.beneficiary);
}
public fun top_up<T>(v: &mut Vesting<T>, funds: Coin<T>) {
    balance::join(&mut v.funds, coin::into_balance(funds));
}
/// Extra deposits cannot reopen vesting or consume unreleased principal.
public fun release_surplus<T>(v: &mut Vesting<T>, ctx: &mut TxContext) {
    let available = balance::value(&v.funds) - (v.principal - v.released);
    assert!(available > 0, ENothingExtra);
    let payment = coin::from_balance(balance::split(&mut v.funds, available), ctx);
    transfer::public_transfer(payment, v.beneficiary);
}
public fun beneficiary<T>(v: &Vesting<T>): address { v.beneficiary }
public fun released<T>(v: &Vesting<T>): u64 { v.released }
