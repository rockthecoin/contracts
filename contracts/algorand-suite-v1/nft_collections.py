"""Native ASA NFT collections. NFTs stay wallet-visible; ARC-19 updates are optional."""
from algopy import Account, Asset, BoxMap, Bytes, Global, Txn, UInt64, arc4, gtxn, itxn, op, urange, ensure_budget, OpUpFeeSource
from common import Service

ARC19 = b"template-ipfs://{ipfscid:1:raw:reserve:sha2-256}"

class CollectionConfig(arc4.Struct):
    name: arc4.String
    symbol: arc4.String
    metadata_uri: arc4.String
    maximum: arc4.UInt64
    metadata_mutable: arc4.Bool
    item_metadata_mutable: arc4.Bool
    royalty_bps: arc4.UInt64
    royalty_ceiling_bps: arc4.UInt64
    royalty_recipient: arc4.Address
    royalty_mutable: arc4.Bool

class CollectionState(arc4.Struct):
    creator: arc4.Address
    owner: arc4.Address
    pending: arc4.Address
    config: CollectionConfig
    minted: arc4.UInt64
    closed: arc4.Bool
    paused: arc4.Bool

class ItemState(arc4.Struct):
    asset: arc4.UInt64
    mutable: arc4.Bool
    destroyed: arc4.Bool

class RockTheCoinAlgorandCollectionsV1(Service, avm_version=11):
    def __init__(self) -> None:
        super().__init__()
        self.collections = BoxMap(Bytes, CollectionState, key_prefix=b"c")
        self.items = BoxMap(Bytes, ItemState, key_prefix=b"i")
        self.roles = BoxMap(Bytes, UInt64, key_prefix=b"a")

    @arc4.abimethod
    def register(self, funding: gtxn.PaymentTransaction, payment: gtxn.PaymentTransaction,
                 config: CollectionConfig, reference: Bytes, fee: UInt64, expiry: UInt64, signature: Bytes) -> None:
        floor = self.funded(funding)
        self.quote(payment, op.sha256(Bytes(b"collection") + config.bytes), reference, fee, expiry, signature)
        assert reference not in self.collections and config.maximum.native > 0
        assert config.name.native.bytes.length > 0 and config.name.native.bytes.length <= 64
        assert config.symbol.native.bytes.length > 0 and config.symbol.native.bytes.length <= 8
        assert config.metadata_uri.native.bytes.length > 0 and config.metadata_uri.native.bytes.length <= 128
        assert config.royalty_bps.native <= config.royalty_ceiling_bps.native and config.royalty_ceiling_bps.native <= 2000
        assert config.royalty_recipient.native != Global.zero_address
        self.collections[reference] = CollectionState(arc4.Address(Txn.sender), arc4.Address(Txn.sender), arc4.Address(), config.copy(), arc4.UInt64(0), arc4.Bool(False), arc4.Bool(False))
        self.refund(floor)

    @arc4.abimethod
    def mint(self, reference: Bytes, count: UInt64) -> None:
        assert Txn.rekey_to == Global.zero_address and count > 0 and count <= 8
        ensure_budget(count * 350 + 800, fee_source=OpUpFeeSource.GroupCredit)
        assert Txn.group_index >= count + 1
        start = Txn.group_index - count - 1
        funding = gtxn.PaymentTransaction(start)
        assert funding.type == 1
        floor = self.funded(funding)
        s = self.collections[reference].copy()
        assert Txn.sender == s.owner.native or self.roles.get(op.sha256(reference + Txn.sender.bytes), default=UInt64(0)) & 1 != 0
        assert not s.closed.native and not s.paused.native
        assert s.minted.native + count <= s.config.maximum.native
        for n in urange(count):
            creation = gtxn.AssetConfigTransaction(start + n + 1)
            assert creation.type == 3 and creation.config_asset.id == 0 and creation.sender == Txn.sender
            assert creation.rekey_to == Global.zero_address and creation.total == 1 and creation.decimals == 0
            assert creation.manager == Global.current_application_address and not creation.default_frozen
            assert creation.freeze == Global.zero_address and creation.clawback == Global.zero_address
            assert creation.asset_name.length > 0 and creation.asset_name.length <= 32
            assert creation.unit_name.length > 0 and creation.unit_name.length <= 8
            if s.config.item_metadata_mutable.native:
                assert (creation.url == ARC19 or creation.url == b"template-ipfs://{ipfscid:1:dag-pb:reserve:sha2-256}") and creation.reserve != Global.zero_address
            else:
                assert creation.url.length > 5 and creation.url[creation.url.length - 5:] == b"#arc3"
            key = reference + op.itob(s.minted.native + n)
            assert key not in self.items
            self.items[key] = ItemState(arc4.UInt64(creation.created_asset.id), s.config.item_metadata_mutable, arc4.Bool(False))
        s.minted = arc4.UInt64(s.minted.native + count)
        self.collections[reference] = s.copy()
        self.refund(floor)

    @arc4.abimethod
    def minting(self, reference: Bytes, paused: bool, close: bool) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        assert not s.closed.native
        s.paused = arc4.Bool(paused)
        if close:
            s.closed = arc4.Bool(True)
        self.collections[reference] = s.copy()

    @arc4.abimethod
    def permissions(self, funding: gtxn.PaymentTransaction, reference: Bytes, account: Account, mask: UInt64) -> None:
        floor = self.funded(funding)
        s = self.collections[reference].copy()
        assert Txn.sender == s.owner.native and account != Global.zero_address and mask < 4
        self.roles[op.sha256(reference + account.bytes)] = mask
        self.refund(floor)

    @arc4.abimethod
    def metadata(self, funding: gtxn.PaymentTransaction, reference: Bytes, uri: Bytes, immutable: bool) -> None:
        floor = self.funded(funding)
        s = self.collections[reference].copy()
        assert Txn.sender == s.owner.native or self.roles.get(op.sha256(reference + Txn.sender.bytes), default=UInt64(0)) & 2 != 0
        assert s.config.metadata_mutable.native and uri.length > 0 and uri.length <= 128
        s.config.metadata_uri = arc4.String.from_bytes(op.itob(uri.length)[6:] + uri)
        if immutable:
            s.config.metadata_mutable = arc4.Bool(False)
        self.collections[reference] = s.copy()
        self.refund(floor)

    @arc4.abimethod
    def item_metadata(self, reference: Bytes, index: UInt64, asset: Asset, reserve: Account, immutable: bool) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address
        assert Txn.sender == s.owner.native or self.roles.get(op.sha256(reference + Txn.sender.bytes), default=UInt64(0)) & 2 != 0
        key = reference + op.itob(index)
        item = self.items[key].copy()
        assert item.asset.native == asset.id and item.mutable.native and not item.destroyed.native and reserve != Global.zero_address
        assert asset.url == ARC19 or asset.url == b"template-ipfs://{ipfscid:1:dag-pb:reserve:sha2-256}"
        if immutable:
            item.mutable = arc4.Bool(False)
        self.items[key] = item.copy()
        itxn.AssetConfig(config_asset=asset, manager=Global.current_application_address, reserve=reserve, freeze=Global.zero_address, clawback=Global.zero_address, fee=0).submit()

    @arc4.abimethod
    def royalty(self, reference: Bytes, recipient: Account, basis_points: UInt64, immutable: bool) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        assert s.config.royalty_mutable.native and recipient != Global.zero_address and basis_points <= s.config.royalty_ceiling_bps.native
        s.config.royalty_bps = arc4.UInt64(basis_points)
        s.config.royalty_recipient = arc4.Address(recipient)
        if immutable:
            s.config.royalty_mutable = arc4.Bool(False)
        self.collections[reference] = s.copy()

    @arc4.abimethod
    def destroy_item(self, reference: Bytes, index: UInt64, asset: Asset) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        key = reference + op.itob(index)
        item = self.items[key].copy()
        assert item.asset.native == asset.id and not item.destroyed.native
        assert asset.creator == Txn.sender and asset.balance(Txn.sender) == 1
        item.destroyed = arc4.Bool(True)
        self.items[key] = item.copy()
        itxn.AssetConfig(config_asset=asset, fee=0).submit()

    @arc4.abimethod
    def transfer_ownership(self, reference: Bytes, successor: Account) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        s.pending = arc4.Address(successor)
        self.collections[reference] = s.copy()

    @arc4.abimethod
    def accept_ownership(self, reference: Bytes) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.pending.native and Txn.sender != Global.zero_address
        s.owner = s.pending
        s.pending = arc4.Address()
        self.collections[reference] = s.copy()

    @arc4.abimethod
    def renounce_ownership(self, reference: Bytes) -> None:
        s = self.collections[reference].copy()
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        assert not s.paused.native
        s.closed = arc4.Bool(True)
        s.owner = arc4.Address()
        s.pending = arc4.Address()
        self.collections[reference] = s.copy()

    @arc4.abimethod(readonly=True)
    def collection(self, reference: Bytes) -> CollectionState:
        return self.collections[reference].copy()

    @arc4.abimethod(readonly=True)
    def item(self, reference: Bytes, index: UInt64) -> ItemState:
        return self.items[reference + op.itob(index)].copy()
