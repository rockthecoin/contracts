#[test_only]
module rtc_asset::coin_tests;
use rtc_asset::rtc_coin::{Self, RTC_COIN};
use rtc_suite::coin_control::{Self, Control};
use rtc_suite::vesting::Vesting;
use sui::coin::{Self, Coin, CoinMetadata};
use sui::test_scenario as ts;

#[test]
fun initializer_allocates_and_retains_only_controller_capabilities() {
    let mut s = ts::begin(@0xa);
    rtc_coin::init_for_testing(s.ctx()); s.next_tx(@0xa);
    let mut control = s.take_shared<Control<RTC_COIN>>();
    let funds = s.take_from_sender<Coin<RTC_COIN>>();
    assert!(coin::value(&funds) == 700 && coin_control::supply(&control) == 1000);
    assert!(coin_control::owner(&control) == @0xa && coin_control::maximum_supply(&control) == 2000);
    assert!(ts::has_most_recent_for_address<Coin<RTC_COIN>>(@0xb));
    assert!(ts::has_most_recent_shared<Vesting<RTC_COIN>>());
    assert!(!ts::has_most_recent_for_address<coin::TreasuryCap<RTC_COIN>>(@0xa));
    coin_control::mint(&mut control, 200, @0xc, s.ctx());
    ts::return_to_sender(&s, funds); ts::return_shared(control); s.next_tx(@0xc);
    let funds = s.take_from_sender<Coin<RTC_COIN>>();assert!(coin::value(&funds) == 200);
    ts::return_to_sender(&s, funds);s.end();
}
#[test]
#[expected_failure(abort_code = 2, location = rtc_suite::coin_control)]
fun metadata_freeze_cannot_be_reopened() {
    let mut s = ts::begin(@0xa);rtc_coin::init_for_testing(s.ctx());s.next_tx(@0xa);
    let mut control = s.take_shared<Control<RTC_COIN>>();
    let mut metadata = s.take_shared<CoinMetadata<RTC_COIN>>();
    coin_control::freeze_metadata(&mut control, s.ctx());
    coin_control::update_metadata(&mut control, &mut metadata, std::string::utf8(b"New"),
        std::ascii::string(b"NEW"), std::string::utf8(b""), std::ascii::string(b""),
        std::string::utf8(b""), s.ctx());
    ts::return_shared(control);ts::return_shared(metadata);s.end();
}
