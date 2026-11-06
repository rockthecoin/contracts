"""Segregated per-lock native accounts. No operator withdrawal or early escape path."""
from algopy import Account, Asset, BoxMap, Bytes, Global, Txn, UInt64, arc4, gtxn, itxn, op, subroutine
from common import Service
from escrow_template import PART0, PART1, PART2, PART3, PART4

class LockConfig(arc4.Struct):
    asset: arc4.UInt64
    amount: arc4.UInt64
    beneficiary: arc4.Address
    start: arc4.UInt64
    cliff: arc4.UInt64
    end: arc4.UInt64

class LockState(arc4.Struct):
    creator: arc4.Address
    escrow: arc4.Address
    config: LockConfig
    released: arc4.UInt64

class RockTheCoinAlgorandEscrowsV1(Service, avm_version=11):
    def __init__(self) -> None:
        super().__init__()
        self.locks = BoxMap(Bytes, LockState, key_prefix=b"v")

    @subroutine
    def escrow(self, reference: Bytes, owner: Account, asset: UInt64) -> Account:
        assert reference.length == 32
        program = (Bytes(PART0) + op.itob(Global.current_application_id.id) + Bytes(PART1) + reference
                   + Bytes(PART2) + owner.bytes + Bytes(PART3) + op.itob(asset) + Bytes(PART4))
        return Account(op.sha512_256(Bytes(b"Program") + program))

    @arc4.abimethod
    def setup(self, reference: Bytes, escrow: Account, asset_id: UInt64) -> None:
        assert Txn.rekey_to == Global.zero_address and reference not in self.locks
        assert escrow == self.escrow(reference, Txn.sender, asset_id)
        assert escrow.auth_address == Global.current_application_address
        assert Txn.group_index >= 2
        fund = gtxn.PaymentTransaction(Txn.group_index - 2)
        assert fund.type == 1 and fund.sender == Txn.sender and fund.receiver == escrow
        assert fund.rekey_to == Global.zero_address and fund.close_remainder_to == Global.zero_address
        if asset_id:
            asset = Asset(asset_id)
            assert asset.freeze == Global.zero_address and asset.clawback == Global.zero_address
            itxn.AssetTransfer(sender=escrow, xfer_asset=asset, asset_receiver=escrow, asset_amount=0, fee=0).submit()
        assert escrow.balance >= escrow.min_balance

    @arc4.abimethod
    def register(self, funding: gtxn.PaymentTransaction, deposit: gtxn.Transaction,
                 payment: gtxn.PaymentTransaction, config: LockConfig, reference: Bytes,
                 fee: UInt64, expiry: UInt64, signature: Bytes) -> None:
        floor = self.funded(funding)
        self.quote(payment, op.sha256(Bytes(b"lock") + config.bytes), reference, fee, expiry, signature)
        assert reference not in self.locks and config.amount.native > 0
        assert config.beneficiary.native != Global.zero_address and config.beneficiary.native != Global.current_application_address
        assert config.start.native <= config.cliff.native and config.cliff.native <= config.end.native
        # The same authorization cannot be replayed after its lock is fully released/deleted.
        assert config.end.native > expiry
        escrow = self.escrow(reference, Txn.sender, config.asset.native)
        assert escrow.auth_address == Global.current_application_address and config.beneficiary.native != escrow
        assert deposit.sender == Txn.sender and deposit.rekey_to == Global.zero_address
        if config.asset.native:
            assert deposit.type == 4 and deposit.xfer_asset.id == config.asset.native
            assert deposit.asset_receiver == escrow and deposit.asset_amount == config.amount.native
            assert deposit.asset_sender == Global.zero_address and deposit.asset_close_to == Global.zero_address
            asset = Asset(config.asset.native)
            assert asset.freeze == Global.zero_address and asset.clawback == Global.zero_address
            assert asset.balance(escrow) >= config.amount.native
        else:
            assert deposit.type == 1 and deposit.receiver == escrow and deposit.amount == config.amount.native
            assert deposit.close_remainder_to == Global.zero_address
            assert escrow.balance >= escrow.min_balance + config.amount.native
        self.locks[reference] = LockState(arc4.Address(Txn.sender), arc4.Address(escrow), config.copy(), arc4.UInt64(0))
        self.refund(floor)

    @subroutine
    def send(self, escrow: Account, asset: UInt64, recipient: Account, amount: UInt64) -> None:
        if asset:
            itxn.AssetTransfer(sender=escrow, xfer_asset=Asset(asset), asset_receiver=recipient, asset_amount=amount, fee=0).submit()
        else:
            itxn.Payment(sender=escrow, receiver=recipient, amount=amount, fee=0).submit()

    @arc4.abimethod
    def release(self, reference: Bytes) -> UInt64:
        assert Txn.rekey_to == Global.zero_address
        s = self.locks[reference].copy()
        c = s.config.copy()
        now = Global.latest_timestamp
        assert now >= c.cliff.native
        vested = c.amount.native
        if now < c.end.native:
            assert now > c.start.native and c.end.native > c.start.native
            hi, lo = op.mulw(c.amount.native, now - c.start.native)
            vested = op.divw(hi, lo, c.end.native - c.start.native)
        amount = vested - s.released.native
        assert amount > 0
        s.released = arc4.UInt64(vested)
        self.locks[reference] = s.copy()
        self.send(s.escrow.native, c.asset.native, c.beneficiary.native, amount)
        remaining = c.amount.native - vested
        if c.asset.native:
            assert Asset(c.asset.native).balance(s.escrow.native) >= remaining
        else:
            assert s.escrow.native.balance >= s.escrow.native.min_balance + remaining
        return amount

    @arc4.abimethod
    def surplus(self, reference: Bytes, native: bool) -> UInt64:
        assert Txn.rekey_to == Global.zero_address
        s = self.locks[reference].copy()
        assert Txn.sender == s.config.beneficiary.native
        remaining = s.config.amount.native - s.released.native
        asset_id = UInt64(0) if native else s.config.asset.native
        if asset_id:
            amount = Asset(asset_id).balance(s.escrow.native) - remaining
        else:
            principal = remaining if s.config.asset.native == 0 else UInt64(0)
            amount = s.escrow.native.balance - s.escrow.native.min_balance - principal
        assert amount > 0
        self.send(s.escrow.native, asset_id, s.config.beneficiary.native, amount)
        return amount

    @arc4.abimethod
    def close(self, reference: Bytes) -> None:
        assert Txn.rekey_to == Global.zero_address
        s = self.locks[reference].copy()
        assert s.released.native == s.config.amount.native and Global.latest_timestamp >= s.config.end.native
        if s.config.asset.native:
            itxn.AssetTransfer(sender=s.escrow.native, xfer_asset=Asset(s.config.asset.native),
                asset_receiver=s.config.beneficiary.native, asset_amount=0, asset_close_to=s.config.beneficiary.native, fee=0).submit()
        itxn.Payment(sender=s.escrow.native, receiver=s.config.beneficiary.native, amount=0,
            close_remainder_to=s.config.beneficiary.native, fee=0).submit()
        previous = Global.current_application_address.min_balance
        del self.locks[reference]
        storage_refund = previous - Global.current_application_address.min_balance
        itxn.Payment(receiver=s.creator.native, amount=storage_refund, fee=0).submit()

    @arc4.abimethod(readonly=True)
    def lock(self, reference: Bytes) -> LockState:
        return self.locks[reference].copy()
