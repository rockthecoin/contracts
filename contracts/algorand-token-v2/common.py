"""Immutable native Algorand services. Owner configuration never controls customer assets."""
from algopy import ARC4Contract, Account, Bytes, Global, Txn, UInt64, arc4, gtxn, itxn, op, subroutine, ensure_budget, OpUpFeeSource

class Service(ARC4Contract):
    def __init__(self) -> None:
        self.owner = Account()
        self.pending_owner = Account()
        self.treasury = Account()
        self.signer = Bytes()
        self.paused = False
        self.version = UInt64(1)

    @arc4.abimethod(create="require")
    def create(self, treasury: Account, signer: Bytes) -> None:
        assert treasury != Global.zero_address and signer.length == 32
        assert Txn.rekey_to == Global.zero_address
        self.owner = Txn.sender
        self.treasury = treasury
        self.signer = signer

    @arc4.abimethod
    def configure(self, treasury: Account, signer: Bytes, paused: bool) -> None:
        assert Txn.sender == self.owner and treasury != Global.zero_address
        assert signer.length == 32 and Txn.rekey_to == Global.zero_address
        self.treasury = treasury
        self.signer = signer
        self.paused = paused

    @arc4.abimethod
    def nominate_operator(self, successor: Account) -> None:
        assert Txn.sender == self.owner and Txn.rekey_to == Global.zero_address
        self.pending_owner = successor

    @arc4.abimethod
    def accept_operator(self) -> None:
        assert Txn.sender == self.pending_owner and Txn.sender != Global.zero_address
        assert Txn.rekey_to == Global.zero_address
        self.owner = Txn.sender
        self.pending_owner = Account()

    @arc4.abimethod
    def resources(self) -> None:
        # AVM group resource/budget carrier. It cannot mutate application state.
        assert Txn.rekey_to == Global.zero_address

    @subroutine
    def quote(self, payment: gtxn.PaymentTransaction, digest: Bytes, reference: Bytes,
              fee: UInt64, expiry: UInt64, signature: Bytes) -> None:
        assert not self.paused and Txn.rekey_to == Global.zero_address
        assert reference.length == 32 and Txn.lease == reference
        assert expiry >= Global.latest_timestamp and expiry <= Global.latest_timestamp + 300
        assert Txn.last_valid > Txn.first_valid and Txn.last_valid - Txn.first_valid <= 100
        assert payment.sender == Txn.sender and payment.receiver == self.treasury
        assert payment.amount == fee and payment.close_remainder_to == Global.zero_address
        assert payment.rekey_to == Global.zero_address
        message = (Bytes(b"RTC_ALGO_QUOTE_V1") + Global.genesis_hash + op.itob(Global.current_application_id.id)
                   + Txn.sender.bytes + reference + op.itob(fee) + op.itob(expiry)
                   + op.itob(Txn.first_valid) + op.itob(Txn.last_valid) + digest)
        ensure_budget(2500, fee_source=OpUpFeeSource.GroupCredit)
        assert op.ed25519verify_bare(message, signature, self.signer)

    @subroutine
    def funded(self, payment: gtxn.PaymentTransaction) -> UInt64:
        assert Txn.rekey_to == Global.zero_address
        assert payment.sender == Txn.sender and payment.receiver == Global.current_application_address
        assert payment.rekey_to == Global.zero_address and payment.close_remainder_to == Global.zero_address
        account = Global.current_application_address
        previous = account.balance - payment.amount
        return previous - account.min_balance if previous >= account.min_balance else UInt64(0)

    @subroutine
    def refund(self, floor: UInt64) -> None:
        account = Global.current_application_address
        assert account.balance >= account.min_balance + floor
        amount = account.balance - account.min_balance - floor
        if amount:
            itxn.Payment(receiver=Txn.sender, amount=amount, fee=0).submit()
