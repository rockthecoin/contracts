module rtc_asset::rtc_nft;

use std::string::{Self, String};
use sui::display;
use sui::event;
use sui::package;
use sui::transfer_policy;
use rtc_suite::collection::{Self, Collection};

public struct RTC_NFT has drop {}
public struct Nft has key, store {
    id: UID, collection: ID, serial: u64, name: String, symbol: String,
    description: String, image_url: String, metadata_uri: String, frozen: bool,
}
public struct Created has copy, drop { quote_id: vector<u8>, creator: address, collection: ID, policy: ID }
public struct Minted has copy, drop { collection: ID, item: ID, serial: u64, recipient: address }
public struct Burned has copy, drop { collection: ID, item: ID, serial: u64 }

const QUOTE_ID: vector<u8> = b"RTC_SUITE_QUOTE_V1";
const NAME: vector<u8> = b"RTC_SUITE_NFT_NAME_V1";
const SYMBOL: vector<u8> = b"RTC_SUITE_NFT_SYMBOL_V1";
const DESCRIPTION: vector<u8> = b"RTC_SUITE_NFT_DESCRIPTION_V1";
const IMAGE_URL: vector<u8> = b"RTC_SUITE_NFT_IMAGE_V1";
const METADATA_URI: vector<u8> = b"RTC_SUITE_NFT_METADATA_V1";
const MAXIMUM: u64 = 18446744073709551002;
const FLAGS: u64 = 9223372036854775001;
const ROYALTY: u16 = 65001;
const ROYALTY_MAXIMUM: u16 = 65002;
const OWNER: address = @0x7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c;
const ROYALTY_TO: address = @0x7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e;
const DELEGATES: vector<address> = vector[@0x7101];
const MASKS: vector<u64> = vector[7101];

#[allow(deprecated_usage, lint(share_owned))]
fun init(witness: RTC_NFT, ctx: &mut TxContext) {
    assert!(QUOTE_ID.length() == 32 && (FLAGS & 14) == FLAGS, 1);
    let publisher = package::claim(witness, ctx);
    let mut display = display::new_with_fields<Nft>(&publisher,
        vector[string::utf8(b"name"), string::utf8(b"description"),
            string::utf8(b"image_url"), string::utf8(b"link")],
        vector[string::utf8(b"{name}"), string::utf8(b"{description}"),
            string::utf8(b"{image_url}"), string::utf8(b"{metadata_uri}")], ctx);
    display.update_version(); transfer::public_freeze_object(display);
    let (mut policy, cap) = transfer_policy::new<Nft>(&publisher, ctx);
    // A frozen Publisher would let anyone create another policy for this type.
    package::burn_publisher(publisher);
    let collection = collection::new(&mut policy, cap, OWNER, DELEGATES, MASKS,
        string::utf8(NAME), string::utf8(SYMBOL), string::utf8(DESCRIPTION),
        string::utf8(IMAGE_URL), string::utf8(METADATA_URI), MAXIMUM,
        (FLAGS & 2) != 0, (FLAGS & 4) != 0, ROYALTY, ROYALTY_TO,
        ROYALTY_MAXIMUM, (FLAGS & 8) != 0, ctx);
    event::emit(Created { quote_id: QUOTE_ID, creator: ctx.sender(),
        collection: object::id(&collection), policy: object::id(&policy) });
    transfer::public_share_object(policy); transfer::public_share_object(collection);
}

public fun mint(c: &mut Collection<Nft>, name: String, description: String,
    image_url: String, metadata_uri: String, frozen: bool, recipient: address,
    ctx: &mut TxContext) {
    check_fields(&name, &description, &image_url, &metadata_uri);
    assert!(recipient != @0x0, 1);
    let (collection, serial) = collection::consume_ticket(collection::authorize_mint(c, ctx));
    let nft = Nft { id: object::new(ctx), collection, serial, name,
        symbol: string::utf8(SYMBOL), description, image_url, metadata_uri,
        frozen: frozen || !collection::metadata_mutable(c) };
    event::emit(Minted { collection, item: object::id(&nft), serial, recipient });
    transfer::public_transfer(nft, recipient);
}
/// An owned NFT also needs its holder's approval as a mutable transaction input.
public fun update(c: &Collection<Nft>, nft: &mut Nft, name: String,
    description: String, image_url: String, metadata_uri: String, freeze: bool,
    ctx: &TxContext) {
    collection::assert_metadata(c, ctx);
    assert!(nft.collection == object::id(c) && !nft.frozen, 2);
    check_fields(&name, &description, &image_url, &metadata_uri);
    nft.name = name; nft.description = description; nft.image_url = image_url;
    nft.metadata_uri = metadata_uri; nft.frozen = freeze;
}
public fun burn(c: &Collection<Nft>, nft: Nft) {
    assert!(collection::burnable(c) && nft.collection == object::id(c), 3);
    let Nft { id, collection, serial, name: _, symbol: _, description: _,
        image_url: _, metadata_uri: _, frozen: _ } = nft;
    event::emit(Burned { collection, item: object::uid_to_inner(&id), serial });
    object::delete(id);
}
fun check_fields(name: &String, description: &String, image_url: &String, uri: &String) {
    assert!(name.length() > 0 && name.length() <= 32 && description.length() <= 2000 &&
        image_url.length() > 0 && image_url.length() <= 500 && uri.length() <= 600, 1);
}
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(RTC_NFT {}, ctx); }
