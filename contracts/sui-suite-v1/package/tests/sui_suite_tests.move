#[test_only]
module rtc_suite::sui_suite_tests;

use rtc_suite::authority;
use rtc_suite::coin_control::{Self, Control};
use rtc_suite::vesting::{Self, Vesting};
use rtc_suite::object_lock::{Self, Lock};
use rtc_suite::distribution;
use rtc_suite::royalty;
use rtc_suite::collection;
use sui::coin::{Self, Coin};
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::transfer_policy;

public struct SUI_SUITE_TESTS has drop {}
public struct Asset has key, store { id: UID }

#[allow(deprecated_usage)]
fun coin_setup(owner: address, mintable: bool, lifetime: bool, maximum: u64): Scenario {
    coin_setup_meta(owner, mintable, lifetime, maximum, false)
}
#[allow(deprecated_usage)]
fun coin_setup_meta(owner: address, mintable: bool, lifetime: bool, maximum: u64,
    metadata_mutable: bool): Scenario {
    let mut s = test_scenario::begin(@0xa);
    let (treasury, metadata) = coin::create_currency(SUI_SUITE_TESTS {}, 6,
        b"RTC", b"Rock", b"Unit test", option::none(), s.ctx());
    let (control, funds) = coin_control::new(treasury, metadata, option::none(), owner,
        vector[], vector[], 1000, maximum, lifetime, mintable, true, metadata_mutable, false, false,
        std::string::utf8(b"ipfs://test"), s.ctx());
    transfer::public_share_object(control); transfer::public_transfer(funds, @0xa);
    s.next_tx(@0xa); s
}
#[allow(deprecated_usage)]
fun regulated_setup(): Scenario {
    let mut s = test_scenario::begin(@0x0);
    sui::deny_list::create_for_testing(s.ctx());
    s.next_tx(@0xa);
    let (treasury, deny, metadata) = coin::create_regulated_currency_v2(SUI_SUITE_TESTS {},
        6, b"RTC", b"Rock", b"Unit test", option::none(), true, s.ctx());
    let (control, funds) = coin_control::new(treasury, metadata, option::some(deny), @0xa,
        vector[], vector[], 1000, 2000, true, true, true, true, true, true,
        std::string::utf8(b"ipfs://test"), s.ctx());
    transfer::public_share_object(control); transfer::public_transfer(funds, @0xa);
    s.next_tx(@0xa); s
}

#[test]
fun native_blocklist_and_pause_can_be_cleared_before_renouncing() {
    let mut s = regulated_setup();
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let mut deny = test_scenario::take_shared<sui::deny_list::DenyList>(&s);
    coin_control::set_blocked(&mut c, &mut deny, @0xb, true, s.ctx());
    assert!(coin::deny_list_v2_contains_next_epoch<SUI_SUITE_TESTS>(&deny, @0xb), 0);
    coin_control::set_paused(&mut c, &mut deny, true, s.ctx());
    assert!(coin::deny_list_v2_is_global_pause_enabled_next_epoch<SUI_SUITE_TESTS>(&deny), 0);
    coin_control::set_paused(&mut c, &mut deny, false, s.ctx());
    coin_control::set_blocked(&mut c, &mut deny, @0xb, false, s.ctx());
    coin_control::renounce_owner(&mut c, s.ctx()); assert!(coin_control::owner(&c) == @0x0, 0);
    test_scenario::return_shared(c); test_scenario::return_shared(deny); s.end();
}
#[test, expected_failure(abort_code=6, location=rtc_suite::coin_control)]
fun paused_token_owner_cannot_renounce_into_a_permanent_freeze() {
    let mut s = regulated_setup();
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let mut deny = test_scenario::take_shared<sui::deny_list::DenyList>(&s);
    coin_control::set_paused(&mut c, &mut deny, true, s.ctx());
    coin_control::renounce_owner(&mut c, s.ctx());
    test_scenario::return_shared(c); test_scenario::return_shared(deny); s.end();
}
#[test, expected_failure(abort_code=6, location=rtc_suite::coin_control)]
fun blocklisted_accounts_must_be_cleared_before_revocation() {
    let mut s = regulated_setup();
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let mut deny = test_scenario::take_shared<sui::deny_list::DenyList>(&s);
    coin_control::set_blocked(&mut c, &mut deny, @0xb, true, s.ctx());
    coin_control::revoke_regulation(&mut c, s.ctx());
    test_scenario::return_shared(c); test_scenario::return_shared(deny); s.end();
}
#[test, expected_failure(abort_code=2, location=rtc_suite::coin_control)]
fun frozen_metadata_cannot_be_edited_again() {
    let mut s = coin_setup_meta(@0xa, true, true, 2000, true);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let mut metadata = test_scenario::take_shared<coin::CoinMetadata<SUI_SUITE_TESTS>>(&s);
    coin_control::freeze_metadata(&mut c, s.ctx());
    coin_control::update_metadata(&mut c, &mut metadata, std::string::utf8(b"New"), std::ascii::string(b"RTC"),
        std::string::utf8(b""), std::ascii::string(b"https://example.org/image.png"),
        std::string::utf8(b"ipfs://new"), s.ctx());
    test_scenario::return_shared(c); test_scenario::return_shared(metadata); s.end();
}

#[test]
fun ownership_transfer_clears_old_delegates() {
    let mut a = authority::new(@0xa);
    authority::set_role(&mut a, @0xa, @0xc, 1);
    authority::assert_role(&a, @0xc, 1);
    authority::nominate(&mut a, @0xa, @0xb);
    authority::accept(&mut a, @0xb);
    assert!(authority::owner(&a) == @0xb, 0);
    authority::destroy_for_testing(a);
}
#[test, expected_failure(abort_code=1, location=rtc_suite::authority)]
fun transfer_does_not_leave_minter_access() {
    let mut a = authority::new(@0xa);
    authority::set_role(&mut a, @0xa, @0xc, 1);
    authority::nominate(&mut a, @0xa, @0xb); authority::accept(&mut a, @0xb);
    authority::assert_role(&a, @0xc, 1); authority::destroy_for_testing(a);
}
#[test, expected_failure(abort_code=1, location=rtc_suite::authority)]
fun only_nominated_owner_can_accept() {
    let mut a = authority::new(@0xa); authority::nominate(&mut a, @0xa, @0xb);
    authority::accept(&mut a, @0xc); authority::destroy_for_testing(a);
}
#[test, expected_failure(abort_code=3, location=rtc_suite::authority)]
fun duplicate_initial_delegates_rejected() {
    let a = authority::with_roles(@0xa, vector[@0xb, @0xb], vector[1, 2]);
    authority::destroy_for_testing(a);
}
#[test]
fun renunciation_is_permanent() {
    let mut a = authority::new(@0xa); authority::set_role(&mut a, @0xa, @0xb, 15);
    authority::renounce(&mut a, @0xa); assert!(authority::owner(&a) == @0x0, 0);
    authority::destroy_for_testing(a);
}
#[test, expected_failure(abort_code=1, location=rtc_suite::authority)]
fun unauthorized_mint_rejected() {
    let mut s = coin_setup(@0xa, true, true, 2000); s.next_tx(@0xb);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    coin_control::mint(&mut c, 1, @0xb, s.ctx());
    test_scenario::return_shared(c); s.end();
}
#[test, expected_failure(abort_code=2, location=rtc_suite::coin_control)]
fun revoked_mint_cannot_be_reopened() {
    let mut s = coin_setup(@0xa, true, true, 2000);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    coin_control::revoke_mint(&mut c, s.ctx()); coin_control::mint(&mut c, 1, @0xa, s.ctx());
    test_scenario::return_shared(c); s.end();
}
#[test, expected_failure(abort_code=3, location=rtc_suite::coin_control)]
fun lifetime_cap_does_not_reopen_after_burn() {
    let mut s = coin_setup(@0xa, true, true, 1000);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let funds = s.take_from_sender<Coin<SUI_SUITE_TESTS>>();
    coin_control::burn(&mut c, funds); coin_control::mint(&mut c, 1, @0xa, s.ctx());
    test_scenario::return_shared(c); s.end();
}
#[test]
fun current_supply_cap_can_reopen_after_burn() {
    let mut s = coin_setup(@0xa, true, false, 1000);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    let funds = s.take_from_sender<Coin<SUI_SUITE_TESTS>>();
    coin_control::burn(&mut c, funds); coin_control::mint(&mut c, 1000, @0xa, s.ctx());
    assert!(coin_control::supply(&c) == 1000, 0);
    test_scenario::return_shared(c); s.end();
}
#[test]
fun ownerless_fixed_coin_still_allows_holder_burning() {
    let mut s = coin_setup(@0x0, false, true, 1000);
    let mut c = test_scenario::take_shared<Control<SUI_SUITE_TESTS>>(&s);
    assert!(coin_control::owner(&c) == @0x0 && !coin_control::mintable(&c), 0);
    let funds = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); coin_control::burn(&mut c, funds);
    assert!(coin_control::supply(&c) == 0, 0); test_scenario::return_shared(c); s.end();
}
#[test]
fun cliff_and_vesting_rounding_pay_fixed_beneficiary() {
    let mut s = test_scenario::begin(@0xa);
    let funds = coin::mint_for_testing<SUI_SUITE_TESTS>(10000, s.ctx());
    vesting::create(funds, @0xb, 1000, 2000, 4000, s.ctx()); s.next_tx(@0xc);
    let mut v = test_scenario::take_shared<Vesting<SUI_SUITE_TESTS>>(&s);
    assert!(vesting::vested(&v, 1999) == 0 && vesting::vested(&v, 2000) == 3333 &&
        vesting::vested(&v, 3999) == 9996 && vesting::vested(&v, 4000) == 10000, 0);
    let mut clock = clock::create_for_testing(s.ctx()); clock::set_for_testing(&mut clock, 2000);
    vesting::release(&mut v, &clock, s.ctx()); assert!(vesting::released(&v) == 3333, 0);
    test_scenario::return_shared(v); clock::destroy_for_testing(clock); s.next_tx(@0xb);
    let paid = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); assert!(coin::value(&paid) == 3333, 0);
    transfer::public_transfer(paid, @0xb); s.end();
}
#[test, expected_failure(abort_code=2, location=rtc_suite::vesting)]
fun vesting_cannot_release_before_cliff() {
    let mut s = test_scenario::begin(@0xa);
    vesting::create(coin::mint_for_testing<SUI_SUITE_TESTS>(1000, s.ctx()), @0xb,
        1000, 2000, 4000, s.ctx()); s.next_tx(@0xa);
    let mut v = test_scenario::take_shared<Vesting<SUI_SUITE_TESTS>>(&s);
    let mut clock = clock::create_for_testing(s.ctx()); clock::set_for_testing(&mut clock, 1999);
    vesting::release(&mut v, &clock, s.ctx()); test_scenario::return_shared(v);
    clock::destroy_for_testing(clock); s.end();
}
#[test]
fun vesting_surplus_leaves_principal_intact() {
    let mut s = test_scenario::begin(@0xa);
    vesting::create(coin::mint_for_testing<SUI_SUITE_TESTS>(1000, s.ctx()), @0xb,
        1000, 2000, 4000, s.ctx()); s.next_tx(@0xc);
    let mut v = test_scenario::take_shared<Vesting<SUI_SUITE_TESTS>>(&s);
    vesting::top_up(&mut v, coin::mint_for_testing<SUI_SUITE_TESTS>(300, s.ctx()));
    vesting::release_surplus(&mut v, s.ctx()); assert!(vesting::released(&v) == 0, 0);
    test_scenario::return_shared(v); s.next_tx(@0xb);
    let paid = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); assert!(coin::value(&paid) == 300, 0);
    transfer::public_transfer(paid, @0xb); s.end();
}
#[test]
fun object_lock_releases_only_to_fixed_beneficiary() {
    let mut s = test_scenario::begin(@0xa);
    let mut clock = clock::create_for_testing(s.ctx()); clock::set_for_testing(&mut clock, 10);
    let asset = Asset { id: object::new(s.ctx()) }; let id = object::id(&asset);
    object_lock::create(asset, @0xb, 20, &clock, s.ctx()); clock::destroy_for_testing(clock);
    s.next_tx(@0xc); let mut lock = test_scenario::take_shared<Lock<Asset>>(&s);
    let mut clock = clock::create_for_testing(s.ctx()); clock::set_for_testing(&mut clock, 20);
    object_lock::release(&mut lock, &clock); clock::destroy_for_testing(clock);
    test_scenario::return_shared(lock); s.next_tx(@0xb);
    let asset = s.take_from_sender<Asset>(); assert!(object::id(&asset) == id, 0);
    transfer::public_transfer(asset, @0xb); s.end();
}
#[test, expected_failure(abort_code=2, location=rtc_suite::object_lock)]
fun object_lock_cannot_release_early() {
    let mut s = test_scenario::begin(@0xa);
    let clock = clock::create_for_testing(s.ctx());
    object_lock::create(Asset { id: object::new(s.ctx()) }, @0xb, 20, &clock, s.ctx());
    clock::destroy_for_testing(clock); s.next_tx(@0xb);
    let mut lock = test_scenario::take_shared<Lock<Asset>>(&s);
    let clock = clock::create_for_testing(s.ctx()); object_lock::release(&mut lock, &clock);
    clock::destroy_for_testing(clock); test_scenario::return_shared(lock); s.end();
}
#[test]
fun multisender_conserves_amounts_and_refunds_sender() {
    let mut s = test_scenario::begin(@0xa);
    distribution::send(coin::mint_for_testing<SUI_SUITE_TESTS>(100, s.ctx()),
        vector[@0xb, @0xc], vector[30, 40], s.ctx()); s.next_tx(@0xb);
    let paid = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); assert!(coin::value(&paid) == 30, 0);
    transfer::public_transfer(paid, @0xb); s.next_tx(@0xc);
    let paid = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); assert!(coin::value(&paid) == 40, 0);
    transfer::public_transfer(paid, @0xc); s.next_tx(@0xa);
    let paid = s.take_from_sender<Coin<SUI_SUITE_TESTS>>(); assert!(coin::value(&paid) == 30, 0);
    transfer::public_transfer(paid, @0xa); s.end();
}
#[test, expected_failure(abort_code=3, location=rtc_suite::distribution)]
fun multisender_total_cannot_wrap_u64() {
    let mut s = test_scenario::begin(@0xa);
    distribution::send(coin::mint_for_testing<SUI_SUITE_TESTS>(100, s.ctx()),
        vector[@0xb, @0xc], vector[18446744073709551615, 2], s.ctx()); s.end();
}
#[test]
fun royalty_ceiling_uses_checked_wide_math() {
    assert!(royalty::due(1, 1) == 1, 0);
    assert!(royalty::due(18446744073709551615, 10000) == 18446744073709551615, 0);
    assert!(royalty::due(10000, 250) == 250 && royalty::due(10000, 0) == 0, 0);
}
#[test]
fun royalty_payment_reaches_creator_not_caller() {
    let mut s = test_scenario::begin(@0xa);
    let (mut policy, cap) = transfer_policy::new_for_testing<Asset>(s.ctx());
    royalty::set(&mut policy, &cap, 100, @0xb);
    let mut request = transfer_policy::new_request<Asset>(object::id_from_address(@0x10),
        1000, object::id_from_address(@0x20));
    let remainder = royalty::pay(&policy, &mut request,
        coin::mint_for_testing<SUI>(10, s.ctx()), s.ctx()); coin::destroy_zero(remainder);
    transfer_policy::confirm_request(&policy, request);
    transfer::public_share_object(policy); transfer::public_transfer(cap, @0xa);
    s.next_tx(@0xb); let paid = s.take_from_sender<Coin<SUI>>();
    assert!(coin::value(&paid) == 10, 0); transfer::public_transfer(paid, @0xb); s.end();
}
#[test, expected_failure(abort_code=3, location=rtc_suite::collection)]
fun collection_lifetime_cap_cannot_be_exceeded() {
    let mut s = test_scenario::begin(@0xa);
    let (mut policy, cap) = transfer_policy::new_for_testing<Asset>(s.ctx());
    let mut c = collection::new(&mut policy, cap, @0xa, vector[], vector[],
        std::string::utf8(b"Rock"), std::string::utf8(b"RTC"), std::string::utf8(b""),
        std::string::utf8(b""), std::string::utf8(b""), 1, true, false,
        0, @0xb, 0, false, s.ctx());
    collection::consume_ticket(collection::authorize_mint(&mut c, s.ctx()));
    collection::consume_ticket(collection::authorize_mint(&mut c, s.ctx()));
    transfer::public_share_object(c); transfer::public_share_object(policy); s.end();
}
