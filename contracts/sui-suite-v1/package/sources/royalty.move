module rtc_suite::royalty;

use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap, TransferRequest};
use sui::event;

const EInvalidRoyalty: u64 = 1;
const EInsufficientPayment: u64 = 2;

public struct Rule has drop {}
public struct Configuration has store, drop { bps: u16, recipient: address }
public struct Paid has copy, drop { item: ID, recipient: address, amount: u64 }

public fun set<T>(policy: &mut TransferPolicy<T>, cap: &TransferPolicyCap<T>,
    bps: u16, recipient: address) {
    assert!(bps <= 10000 && recipient != @0x0, EInvalidRoyalty);
    if (transfer_policy::has_rule<T, Rule>(policy)) {
        transfer_policy::remove_rule<T, Rule, Configuration>(policy, cap);
    };
    transfer_policy::add_rule(Rule {}, policy, cap, Configuration { bps, recipient });
}
public fun due(price: u64, bps: u16): u64 {
    assert!(bps <= 10000, EInvalidRoyalty);
    ((((price as u128) * (bps as u128)) + 9999) / 10000) as u64
}
/// Covers Kiosk trades governed by this policy. Ordinary native NFT transfers
/// are not taxed. The royalty goes straight to the configured creator wallet.
public fun pay<T>(policy: &TransferPolicy<T>, request: &mut TransferRequest<T>,
    mut funds: Coin<SUI>, ctx: &mut TxContext): Coin<SUI> {
    let config: &Configuration = transfer_policy::get_rule(Rule {}, policy);
    let amount = due(transfer_policy::paid(request), config.bps);
    assert!(coin::value(&funds) >= amount, EInsufficientPayment);
    if (amount > 0) transfer::public_transfer(coin::split(&mut funds, amount, ctx), config.recipient);
    event::emit(Paid { item: transfer_policy::item(request), recipient: config.recipient, amount });
    transfer_policy::add_receipt(Rule {}, request);
    funds
}
