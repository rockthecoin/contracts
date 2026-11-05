#[test_only]
module rtc_asset::creator_tests;

use rtc_asset::rtc_nft::{Self, Nft};
use rtc_suite::collection::{Self, Collection};
use sui::package::Publisher;
use sui::test_scenario as ts;
use std::string::utf8;

// scripts/test-sui-creators-v2.mjs patches only a temporary copy with the same
// typed constants used by the customer transaction builder. Production source
// and frozen library bytes are never changed by these native VM tests.
#[test]
fun initialization_mints_once_and_burns_the_publisher() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xa);
    assert!(!ts::has_most_recent_for_address<Publisher>(@0xa));
    assert!(!ts::has_most_recent_immutable<Publisher>());
    let c = s.take_shared<Collection<Nft>>();
    assert!(collection::owner(&c) == @0xa && collection::minted(&c) == 1);
    let item = s.take_from_sender<Nft>();
    // A holder burn never reopens the lifetime collection cap.
    rtc_nft::burn(&c, item); assert!(collection::minted(&c) == 1);
    ts::return_shared(c); s.end();
}

#[test]
fun a_holder_can_freeze_their_item_without_collection_authority() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xa); let item = s.take_from_sender<Nft>();
    transfer::public_transfer(item, @0xc);
    s.next_tx(@0xc); let mut item = s.take_from_sender<Nft>();
    rtc_nft::freeze_item(&mut item); rtc_nft::freeze_item(&mut item);
    transfer::public_transfer(item, @0xa); s.end();
}

#[test]
#[expected_failure(abort_code = 2, location = rtc_asset::rtc_nft)]
fun holder_freeze_is_permanent_even_for_the_collection_owner() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xa); let mut item = s.take_from_sender<Nft>();
    rtc_nft::freeze_item(&mut item); let c = s.take_shared<Collection<Nft>>();
    rtc_nft::update(&c, &mut item, utf8(b"Changed"), utf8(b""),
        utf8(b"ipfs://image"), utf8(b"ipfs://metadata"), false, s.ctx());
    ts::return_shared(c); ts::return_to_sender(&s, item); s.end();
}

#[test]
#[expected_failure(abort_code = 1, location = rtc_suite::authority)]
fun outsiders_cannot_mint() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xc); let mut c = s.take_shared<Collection<Nft>>();
    rtc_nft::mint(&mut c, utf8(b"Item"), utf8(b""), utf8(b"ipfs://image"),
        utf8(b"ipfs://metadata"), false, @0xc, s.ctx());
    ts::return_shared(c); s.end();
}

#[test]
#[expected_failure(abort_code = 3, location = rtc_suite::collection)]
fun initial_mint_consumes_the_lifetime_cap() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xa); let mut c = s.take_shared<Collection<Nft>>();
    rtc_nft::mint(&mut c, utf8(b"Item 2"), utf8(b""), utf8(b"ipfs://image"),
        utf8(b"ipfs://metadata"), false, @0xa, s.ctx());
    rtc_nft::mint(&mut c, utf8(b"Item 3"), utf8(b""), utf8(b"ipfs://image"),
        utf8(b"ipfs://metadata"), false, @0xa, s.ctx());
    ts::return_shared(c); s.end();
}

#[test]
fun an_initial_item_can_be_updated_then_frozen() {
    let mut s = ts::begin(@0xa); rtc_nft::init_for_testing(s.ctx());
    s.next_tx(@0xa); let c = s.take_shared<Collection<Nft>>();
    let mut item = s.take_from_sender<Nft>();
    rtc_nft::update(&c, &mut item, utf8(b"Changed"), utf8(b"Description"),
        utf8(b"ipfs://changed"), utf8(b"ipfs://metadata2"), true, s.ctx());
    rtc_nft::burn(&c, item); ts::return_shared(c); s.end();
}
