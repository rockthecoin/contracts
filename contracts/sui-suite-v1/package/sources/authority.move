module rtc_suite::authority;

use sui::vec_map::{Self, VecMap};

const EUnauthorized: u64 = 1;
const EInvalidOwner: u64 = 2;
const EInvalidRole: u64 = 3;

/// Embedded in each customer's controller, never a platform-wide administrator.
public struct Authority has store {
    owner: address,
    pending_owner: Option<address>,
    roles: VecMap<address, u64>,
}

public fun new(owner: address): Authority {
    assert!(owner != @0x0, EInvalidOwner);
    Authority { owner, pending_owner: option::none(), roles: vec_map::empty() }
}
public fun renounced(): Authority {
    Authority { owner: @0x0, pending_owner: option::none(), roles: vec_map::empty() }
}
public fun with_roles(owner: address, recipients: vector<address>, masks: vector<u64>): Authority {
    assert!(recipients.length() == masks.length() && recipients.length() <= 32, EInvalidRole);
    let mut a = new(owner); let mut seen = sui::vec_set::empty(); let mut i = 0;
    while (i < recipients.length()) {
        assert!(!seen.contains(&recipients[i]), EInvalidRole);
        seen.insert(recipients[i]); set_role(&mut a, owner, recipients[i], masks[i]);
        i = i + 1;
    };
    a
}

public fun owner(a: &Authority): address { a.owner }
public fun pending_owner(a: &Authority): Option<address> { a.pending_owner }
public fun assert_owner(a: &Authority, sender: address) {
    assert!(sender != @0x0 && a.owner == sender, EUnauthorized);
}
public fun assert_role(a: &Authority, sender: address, role: u64) {
    assert!(sender != @0x0 && (a.owner == sender ||
        (a.roles.contains(&sender) && (*a.roles.get(&sender) & role) == role)), EUnauthorized);
}
public fun set_role(a: &mut Authority, sender: address, recipient: address, mask: u64) {
    assert_owner(a, sender);
    assert!(recipient != @0x0 && mask <= 15, EInvalidRole);
    if (a.roles.contains(&recipient)) { a.roles.remove(&recipient); };
    if (mask > 0) a.roles.insert(recipient, mask);
}
public fun nominate(a: &mut Authority, sender: address, recipient: address) {
    assert_owner(a, sender);
    assert!(recipient != @0x0 && recipient != sender, EInvalidOwner);
    a.pending_owner = option::some(recipient);
}
public fun cancel_nomination(a: &mut Authority, sender: address) {
    assert_owner(a, sender); a.pending_owner = option::none();
}
public fun accept(a: &mut Authority, sender: address) {
    assert!(a.pending_owner.is_some() && *a.pending_owner.borrow() == sender, EUnauthorized);
    a.owner = sender; a.pending_owner = option::none();
    // An outgoing owner cannot leave delegates active behind the new owner.
    a.roles = vec_map::empty();
}
public fun renounce(a: &mut Authority, sender: address) {
    assert_owner(a, sender);
    a.owner = @0x0; a.pending_owner = option::none(); a.roles = vec_map::empty();
}
#[test_only]
public fun destroy_for_testing(a: Authority) {
    let Authority { owner: _, pending_owner: _, roles: _ } = a;
}
