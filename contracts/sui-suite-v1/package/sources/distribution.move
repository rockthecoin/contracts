module rtc_suite::distribution;

use sui::coin::{Self, Coin};
use sui::event;

const EInvalidRecipients: u64 = 1;
const EInvalidAmount: u64 = 2;
const EInsufficientFunds: u64 = 3;

public struct Distributed has copy, drop { sender: address, recipients: u64, amount: u64 }

#[allow(lint(self_transfer))]
public fun send<T>(mut funds: Coin<T>, recipients: vector<address>, amounts: vector<u64>,
    ctx: &mut TxContext) {
    let count = recipients.length();
    assert!(count > 0 && count <= 200 && count == amounts.length(), EInvalidRecipients);
    let mut sum: u128 = 0; let mut i = 0;
    while (i < count) {
        assert!(recipients[i] != @0x0 && amounts[i] > 0, EInvalidAmount);
        sum = sum + (amounts[i] as u128); i = i + 1;
    };
    assert!(sum <= (coin::value(&funds) as u128), EInsufficientFunds);
    i = 0;
    while (i < count) {
        transfer::public_transfer(coin::split(&mut funds, amounts[i], ctx), recipients[i]);
        i = i + 1;
    };
    if (coin::value(&funds) == 0) coin::destroy_zero(funds)
    else transfer::public_transfer(funds, ctx.sender());
    event::emit(Distributed { sender: ctx.sender(), recipients: count, amount: sum as u64 });
}
