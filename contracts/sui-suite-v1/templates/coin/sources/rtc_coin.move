module rtc_asset::rtc_coin;

use std::string::{Self, String};
use sui::coin;
use sui::event;
use sui::url;
use rtc_suite::coin_control;
use rtc_suite::vesting;

public struct RTC_COIN has drop {}
public struct Created has copy, drop {
    quote_id: vector<u8>, creator: address, controller: ID, coin_id: ID,
    supply: u64, metadata_uri: String,
}
const QUOTE_ID: vector<u8> = b"RTC_SUITE_QUOTE_V1";
const NAME: vector<u8> = b"RTC_SUITE_COIN_NAME_V1";
const SYMBOL: vector<u8> = b"RTC_SUITE_COIN_SYMBOL_V1";
const DESCRIPTION: vector<u8> = b"RTC_SUITE_COIN_DESCRIPTION_V1";
const ICON_URL: vector<u8> = b"RTC_SUITE_COIN_ICON_V1";
const METADATA_URI: vector<u8> = b"RTC_SUITE_COIN_METADATA_V1";
const DECIMALS: u8 = 253;
const SUPPLY: u64 = 18446744073709551001;
const MAXIMUM: u64 = 18446744073709551002;
// mint, burn, editable metadata, pause, blocklist, lifetime supply cap.
const FLAGS: u64 = 9223372036854775001;
const OWNER: address = @0x7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c;
const RECIPIENT: address = @0x7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e;
const DELEGATES: vector<address> = vector[@0x7101];
const MASKS: vector<u64> = vector[7101];
const ALLOCATIONS: vector<address> = vector[@0x7102];
const AMOUNTS: vector<u64> = vector[7102];
const BENEFICIARIES: vector<address> = vector[@0x7103];
const VEST_AMOUNTS: vector<u64> = vector[7103];
const STARTS: vector<u64> = vector[7104];
const CLIFFS: vector<u64> = vector[7105];
const ENDS: vector<u64> = vector[7106];

#[allow(deprecated_usage, lint(self_transfer), lint(share_owned))]
fun init(witness: RTC_COIN, ctx: &mut TxContext) {
    assert!(QUOTE_ID.length() == 32 && DECIMALS <= 18 && (FLAGS & 63) == FLAGS &&
        NAME.length() > 0 && NAME.length() <= 32 && SYMBOL.length() > 0 &&
        SYMBOL.length() <= 10 && DESCRIPTION.length() <= 2000 &&
        ICON_URL.length() <= 500 && METADATA_URI.length() <= 600, 1);
    let mintable = (FLAGS & 1) != 0;
    let burnable = (FLAGS & 2) != 0;
    let metadata_mutable = (FLAGS & 4) != 0;
    let pause = (FLAGS & 8) != 0;
    let blocklist = (FLAGS & 16) != 0;
    let lifetime = (FLAGS & 32) != 0;
    let icon = option::some(url::new_unsafe_from_bytes(ICON_URL));
    let (treasury, metadata, deny_cap) = if (pause || blocklist) {
        let (treasury, deny_cap, metadata) = coin::create_regulated_currency_v2(
            witness, DECIMALS, SYMBOL, NAME, DESCRIPTION, icon, pause, ctx);
        (treasury, metadata, option::some(deny_cap))
    } else {
        let (treasury, metadata) = coin::create_currency(
            witness, DECIMALS, SYMBOL, NAME, DESCRIPTION, icon, ctx);
        (treasury, metadata, option::none())
    };
    let uri = string::utf8(METADATA_URI);
    let (control, mut funds) = coin_control::new(treasury, metadata, deny_cap,
        OWNER, DELEGATES, MASKS, SUPPLY, MAXIMUM, lifetime, mintable, burnable,
        metadata_mutable, pause, blocklist, uri, ctx);
    event::emit(Created { quote_id: QUOTE_ID, creator: ctx.sender(),
        controller: object::id(&control), coin_id: object::id(&funds), supply: SUPPLY, metadata_uri: uri });
    transfer::public_share_object(control);
    assert!(ALLOCATIONS.length() == AMOUNTS.length() && ALLOCATIONS.length() <= 100, 1);
    let mut i = 0;
    while (i < ALLOCATIONS.length()) {
        assert!(ALLOCATIONS[i] != @0x0 && AMOUNTS[i] > 0, 1);
        transfer::public_transfer(coin::split(&mut funds, AMOUNTS[i], ctx), ALLOCATIONS[i]);
        i = i + 1;
    };
    assert!(BENEFICIARIES.length() <= 32 && BENEFICIARIES.length() == VEST_AMOUNTS.length() &&
        BENEFICIARIES.length() == STARTS.length() && BENEFICIARIES.length() == CLIFFS.length() &&
        BENEFICIARIES.length() == ENDS.length(), 1);
    i = 0;
    while (i < BENEFICIARIES.length()) {
        let _ = vesting::create(coin::split(&mut funds, VEST_AMOUNTS[i], ctx),
            BENEFICIARIES[i], STARTS[i], CLIFFS[i], ENDS[i], ctx);
        i = i + 1;
    };
    assert!(RECIPIENT != @0x0, 1);
    if (coin::value(&funds) == 0) coin::destroy_zero(funds)
    else transfer::public_transfer(funds, RECIPIENT);
}
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(RTC_COIN {}, ctx); }
