#[test_only]
module rtc_asset::collection_tests;
use rtc_asset::rtc_nft::{Self, Nft};
use rtc_suite::collection::{Self, Collection};
use sui::package::Publisher;
use sui::test_scenario as ts;
use std::string::utf8;

#[test]
fun collection_mints_edits_and_burns_without_exposing_a_publisher() {
    let mut s = ts::begin(@0xa);rtc_nft::init_for_testing(s.ctx());s.next_tx(@0xa);
    assert!(!ts::has_most_recent_for_address<Publisher>(@0xa) && !ts::has_most_recent_immutable<Publisher>());
    let mut c = s.take_shared<Collection<Nft>>();
    rtc_nft::mint(&mut c, utf8(b"Item 1"), utf8(b""), utf8(b"ipfs://image"), utf8(b"ipfs://meta"), false, @0xa, s.ctx());
    assert!(collection::minted(&c) == 1);ts::return_shared(c);s.next_tx(@0xa);
    let c = s.take_shared<Collection<Nft>>();let mut nft = s.take_from_sender<Nft>();
    rtc_nft::update(&c, &mut nft, utf8(b"Updated"), utf8(b""), utf8(b"ipfs://image"), utf8(b"ipfs://meta"), true, s.ctx());
    rtc_nft::burn(&c, nft);assert!(collection::minted(&c) == 1);ts::return_shared(c);s.end();
}
#[test]
#[expected_failure(abort_code = 1, location = rtc_suite::authority)]
fun outsiders_cannot_mint_into_the_collection() {
    let mut s = ts::begin(@0xa);rtc_nft::init_for_testing(s.ctx());s.next_tx(@0xc);
    let mut c = s.take_shared<Collection<Nft>>();
    rtc_nft::mint(&mut c, utf8(b"Item"), utf8(b""), utf8(b"ipfs://image"), utf8(b""), false, @0xc, s.ctx());
    ts::return_shared(c);s.end();
}
#[test]
#[expected_failure(abort_code = 2, location = rtc_asset::rtc_nft)]
fun a_frozen_item_cannot_be_edited() {
    let mut s = ts::begin(@0xa);rtc_nft::init_for_testing(s.ctx());s.next_tx(@0xa);
    let mut c = s.take_shared<Collection<Nft>>();
    rtc_nft::mint(&mut c, utf8(b"Item"), utf8(b""), utf8(b"ipfs://image"), utf8(b""), true, @0xa, s.ctx());
    ts::return_shared(c);s.next_tx(@0xa);
    let c = s.take_shared<Collection<Nft>>();let mut nft = s.take_from_sender<Nft>();
    rtc_nft::update(&c, &mut nft, utf8(b"New"), utf8(b""), utf8(b"ipfs://image"), utf8(b""), false, s.ctx());
    ts::return_shared(c);ts::return_to_sender(&s, nft);s.end();
}
