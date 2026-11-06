"""Creator-owned native ASAs and explicitly controlled Smart ASAs; no upgrade/delete route."""
from algopy import Account, Asset, BoxMap, Bytes, Global, Txn, UInt64, arc4, gtxn, itxn, op, subroutine, urange, ensure_budget, OpUpFeeSource
from common import Service
from typing import Literal

class TokenConfig(arc4.Struct):
    name: arc4.String
    symbol: arc4.String
    url: arc4.String
    metadata_hash: arc4.StaticArray[arc4.Byte, Literal[32]]
    reserve: arc4.Address
    maximum: arc4.UInt64
    initial: arc4.UInt64
    decimals: arc4.UInt64
    flags: arc4.UInt64
    transfer_bps: arc4.UInt64
    buy_bps: arc4.UInt64
    sell_bps: arc4.UInt64
    maximum_bps: arc4.UInt64
    tax_recipients: arc4.DynamicArray[arc4.Address]
    tax_shares: arc4.DynamicArray[arc4.UInt64]
    maximum_transaction: arc4.UInt64
    maximum_wallet: arc4.UInt64
    cooldown: arc4.UInt64
    trading_start: arc4.UInt64

class TokenState(arc4.Struct):
    asset: arc4.UInt64
    creator: arc4.Address
    owner: arc4.Address
    pending: arc4.Address
    config: TokenConfig
    circulating: arc4.UInt64
    minted: arc4.UInt64
    paused: arc4.Bool
    frozen_count: arc4.UInt64

# flags: mint 1, burn 2, account freeze 4, Smart ASA 8, lifetime cap 16,
# editable taxes 32, editable recipients 64, editable pools 128,
# editable limits 256, editable trading start 512, editable ARC-19 metadata 1024.
# Native ASA transfers remain native. Global pause, taxes and limits are Smart-ASA-only.
class RockTheCoinAlgorandTokensV2(Service, avm_version=11):
    def __init__(self) -> None:
        super().__init__()
        self.version = UInt64(2)
        self.tokens = BoxMap(Bytes, TokenState, key_prefix=b"t")
        self.roles = BoxMap(Bytes, UInt64, key_prefix=b"a")
        self.pools = BoxMap(Bytes, bool, key_prefix=b"p")
        self.exemptions = BoxMap(Bytes, bool, key_prefix=b"e")
        self.limits_exempt = BoxMap(Bytes, bool, key_prefix=b"x")
        self.last_transfer = BoxMap(Bytes, UInt64, key_prefix=b"l")
        self.allowances = BoxMap(Bytes, UInt64, key_prefix=b"s")
        self.delegates = BoxMap(Bytes, Account, key_prefix=b"d")
        self.weights = BoxMap(Bytes, UInt64, key_prefix=b"w")

    @subroutine
    def key(self, reference: Bytes, account: Account) -> Bytes:
        return op.sha256(reference + account.bytes)

    @subroutine
    def authority(self, reference: Bytes, asset: UInt64, mask: UInt64) -> TokenState:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset
        assert Txn.rekey_to == Global.zero_address
        assert Txn.sender == s.owner.native or self.roles.get(self.key(reference, Txn.sender), default=UInt64(0)) & mask != 0
        return s

    @arc4.abimethod
    def register(self, funding: gtxn.PaymentTransaction, creation: gtxn.AssetConfigTransaction,
                 payment: gtxn.PaymentTransaction, config: TokenConfig, reference: Bytes,
                 fee: UInt64, expiry: UInt64, signature: Bytes) -> UInt64:
        floor = self.funded(funding)
        self.quote(payment, op.sha256(Bytes(b"token") + config.bytes), reference, fee, expiry, signature)
        assert reference not in self.tokens and creation.sender == Txn.sender
        assert creation.rekey_to == Global.zero_address and creation.config_asset.id == 0
        assert creation.asset_name == config.name.native.bytes and creation.unit_name == config.symbol.native.bytes
        assert creation.url == config.url.native.bytes and creation.metadata_hash == config.metadata_hash.bytes
        assert creation.total == config.maximum.native and creation.decimals == config.decimals.native
        assert config.maximum.native > 0 and config.initial.native > 0 and config.initial.native <= config.maximum.native
        assert config.decimals.native <= 18 and config.flags.native < 65536
        assert creation.manager == Global.current_application_address and creation.clawback == Global.current_application_address
        smart = config.flags.native & 8 != 0
        assert creation.default_frozen == smart
        assert creation.reserve == config.reserve.native
        assert creation.freeze == (Global.current_application_address if (smart or config.flags.native & 4 != 0) else Global.zero_address)
        assert config.maximum_bps.native <= 2000
        assert config.transfer_bps.native <= config.maximum_bps.native and config.buy_bps.native <= config.maximum_bps.native and config.sell_bps.native <= config.maximum_bps.native
        self.validate_tax(config)
        if not smart:
            assert config.transfer_bps.native == 0 and config.buy_bps.native == 0 and config.sell_bps.native == 0
            assert config.maximum_transaction.native == 0 and config.maximum_wallet.native == 0 and config.cooldown.native == 0 and config.trading_start.native == 0
        asset = creation.created_asset
        assert reference not in self.tokens
        itxn.AssetTransfer(xfer_asset=asset, asset_receiver=Global.current_application_address, asset_amount=0, fee=0).submit()
        reserve_amount = config.maximum.native - config.initial.native
        if reserve_amount:
            itxn.AssetTransfer(xfer_asset=asset, asset_sender=Txn.sender, asset_receiver=Global.current_application_address, asset_amount=reserve_amount, fee=0).submit()
        if smart:
            itxn.AssetFreeze(freeze_asset=asset, freeze_account=Txn.sender, frozen=True, fee=0).submit()
        if not smart and config.flags.native & 8192 == 0:
            itxn.AssetConfig(config_asset=asset, manager=Global.current_application_address,
                reserve=config.reserve.native, freeze=creation.freeze, clawback=Global.zero_address, fee=0).submit()
        if config.flags.native & 2048 != 0:
            assert smart
            self.weights[self.key(reference, Txn.sender)] = config.initial.native
        if config.flags.native & 4096 != 0:
            self.exemptions[self.key(reference, Txn.sender)] = True
            self.limits_exempt[self.key(reference, Txn.sender)] = True
        self.tokens[reference] = TokenState(arc4.UInt64(asset.id), arc4.Address(Txn.sender), arc4.Address(Txn.sender if config.flags.native & 32768 != 0 else Global.zero_address), arc4.Address(), config.copy(), config.initial, config.initial, arc4.Bool(False), arc4.UInt64(0))
        self.refund(floor)
        return asset.id

    @subroutine
    def portion(self, amount: UInt64, basis_points: UInt64) -> UInt64:
        high, low = op.mulw(amount, basis_points)
        return op.divw(high, low, 10000)

    @subroutine
    def validate_tax(self, config: TokenConfig) -> None:
        assert config.tax_recipients.length <= 4 and config.tax_recipients.length == config.tax_shares.length
        total = UInt64(0)
        for n in urange(config.tax_recipients.length):
            assert config.tax_recipients[n].native != Global.zero_address and config.tax_recipients[n].native != Global.current_application_address
            assert config.tax_shares[n].native > 0
            total += config.tax_shares[n].native
        if config.maximum_bps.native:
            assert total == 10000
        else:
            assert total == 0 or total == 10000

    @arc4.abimethod
    def mint(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, recipient: Account, amount: UInt64) -> None:
        floor = self.funded(funding)
        s = self.authority(reference, asset.id, UInt64(1))
        assert s.config.flags.native & 1 != 0 and not s.paused.native and amount > 0
        assert recipient != Global.current_application_address and recipient != Global.zero_address
        assert not self.pools.get(Bytes(b"blocked") + self.key(reference, recipient), default=False)
        if s.config.maximum_wallet.native and not self.limits_exempt.get(self.key(reference, recipient), default=False):
            assert asset.balance(recipient) + amount <= s.config.maximum_wallet.native
        assert s.circulating.native + amount <= s.config.maximum.native
        if s.config.flags.native & 16 != 0:
            assert s.minted.native + amount <= s.config.maximum.native
        s.circulating = arc4.UInt64(s.circulating.native + amount)
        # Circulating-only caps allow reissuance after burns. The informational
        # lifetime counter saturates instead of accidentally imposing uint64's
        # limit on cumulative issuance. Lifetime-capped tokens remain exact.
        maximum_counter = UInt64(18446744073709551615)
        s.minted = arc4.UInt64(s.minted.native + amount if amount <= maximum_counter - s.minted.native else maximum_counter)
        self.tokens[reference] = s.copy()
        if s.config.flags.native & 8 != 0:
            itxn.AssetTransfer(xfer_asset=asset, asset_receiver=recipient, asset_amount=amount,
                asset_sender=Global.current_application_address, fee=0).submit()
        else:
            itxn.AssetTransfer(xfer_asset=asset, asset_receiver=recipient, asset_amount=amount, fee=0).submit()
        self.move_votes(reference, s.config.flags.native, Global.zero_address, recipient, amount)
        assert asset.balance(Global.current_application_address) >= s.config.maximum.native - s.circulating.native
        self.refund(floor)

    @arc4.abimethod
    def burn(self, deposit: gtxn.AssetTransferTransaction, reference: Bytes, asset: Asset) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert s.config.flags.native & 2 != 0 and s.config.flags.native & 8 == 0
        assert Txn.rekey_to == Global.zero_address and deposit.sender == Txn.sender
        assert deposit.asset_sender == Global.zero_address and deposit.asset_close_to == Global.zero_address and deposit.rekey_to == Global.zero_address
        assert deposit.xfer_asset == asset and deposit.asset_receiver == Global.current_application_address and deposit.asset_amount > 0
        s.circulating = arc4.UInt64(s.circulating.native - deposit.asset_amount)
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def smart_burn(self, reference: Bytes, asset: Asset, amount: UInt64) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert Txn.rekey_to == Global.zero_address and s.config.flags.native & 10 == 10
        assert not s.paused.native and amount > 0 and not self.pools.get(Bytes(b"blocked") + self.key(reference, Txn.sender), default=False)
        s.circulating = arc4.UInt64(s.circulating.native - amount)
        self.tokens[reference] = s.copy()
        self.move_votes(reference, s.config.flags.native, Txn.sender, Global.zero_address, amount)
        itxn.AssetTransfer(xfer_asset=asset, asset_sender=Txn.sender, asset_receiver=Global.current_application_address, asset_amount=amount, fee=0).submit()

    @arc4.abimethod
    def pause(self, reference: Bytes, asset: Asset, paused: bool) -> None:
        s = self.authority(reference, asset.id, UInt64(2))
        s.paused = arc4.Bool(paused)
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def freeze(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, account: Account, frozen: bool) -> None:
        s = self.authority(reference, asset.id, UInt64(4))
        assert s.config.flags.native & 4 != 0 and account != Global.current_application_address
        floor = self.funded(funding)
        if s.config.flags.native & 8 != 0:
            key = Bytes(b"blocked") + self.key(reference, account)
            previous = self.pools.get(key, default=False)
            self.pools[key] = frozen
        else:
            previous = asset.frozen(account)
            itxn.AssetFreeze(freeze_asset=asset, freeze_account=account, frozen=frozen, fee=0).submit()
        if previous != frozen:
            s.frozen_count = arc4.UInt64(s.frozen_count.native + 1 if frozen else s.frozen_count.native - 1)
        self.tokens[reference] = s.copy()
        self.refund(floor)

    @arc4.abimethod
    def permissions(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, account: Account, mask: UInt64) -> None:
        floor = self.funded(funding)
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert Txn.sender == s.owner.native and mask < 64 and account != Global.zero_address
        self.roles[self.key(reference, account)] = mask
        self.refund(floor)

    @arc4.abimethod
    def transfer_ownership(self, reference: Bytes, asset: Asset, successor: Account) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        s.pending = arc4.Address(successor)
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def accept_ownership(self, reference: Bytes, asset: Asset) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.pending.native and Txn.sender != Global.zero_address
        s.owner = s.pending
        s.pending = arc4.Address()
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def renounce_ownership(self, reference: Bytes, asset: Asset) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert Txn.rekey_to == Global.zero_address and Txn.sender == s.owner.native
        assert not s.paused.native and s.frozen_count.native == 0
        # Delegated roles are separately visible and individually revoked by the creator.
        s.owner = arc4.Address()
        s.pending = arc4.Address()
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def revoke_mint(self, reference: Bytes, asset: Asset) -> None:
        s = self.authority(reference, asset.id, UInt64(1))
        assert Txn.sender == s.owner.native
        s.config.flags = arc4.UInt64(s.config.flags.native & ~UInt64(1))
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def metadata(self, reference: Bytes, asset: Asset, reserve: Account, immutable: bool) -> None:
        s = self.authority(reference, asset.id, UInt64(8))
        assert s.config.flags.native & 1024 != 0 and reserve != Global.zero_address
        s.config.reserve = arc4.Address(reserve)
        if immutable:
            s.config.flags = arc4.UInt64(s.config.flags.native & ~UInt64(1024))
        self.tokens[reference] = s.copy()
        itxn.AssetConfig(config_asset=asset, manager=Global.current_application_address,
            reserve=reserve, freeze=asset.freeze, clawback=asset.clawback, fee=0).submit()

    @arc4.abimethod
    def tax(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, transfer_bps: UInt64, buy_bps: UInt64, sell_bps: UInt64,
            recipients: arc4.DynamicArray[arc4.Address], shares: arc4.DynamicArray[arc4.UInt64]) -> None:
        floor = self.funded(funding)
        s = self.authority(reference, asset.id, UInt64(16))
        assert s.config.flags.native & 8 != 0
        if transfer_bps != s.config.transfer_bps.native or buy_bps != s.config.buy_bps.native or sell_bps != s.config.sell_bps.native:
            assert s.config.flags.native & 32 != 0
        if recipients.bytes != s.config.tax_recipients.bytes or shares.bytes != s.config.tax_shares.bytes:
            assert s.config.flags.native & 64 != 0
        assert transfer_bps <= s.config.maximum_bps.native and buy_bps <= s.config.maximum_bps.native and sell_bps <= s.config.maximum_bps.native
        s.config.transfer_bps = arc4.UInt64(transfer_bps)
        s.config.buy_bps = arc4.UInt64(buy_bps)
        s.config.sell_bps = arc4.UInt64(sell_bps)
        s.config.tax_recipients = recipients.copy()
        s.config.tax_shares = shares.copy()
        self.validate_tax(s.config.copy())
        self.tokens[reference] = s.copy()
        self.refund(floor)

    @arc4.abimethod
    def account_policy(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, account: Account, kind: UInt64, value: bool) -> None:
        floor = self.funded(funding)
        s = self.authority(reference, asset.id, UInt64(16))
        assert s.config.flags.native & 8 != 0 and account != Global.zero_address
        key = self.key(reference, account)
        if kind == 0:
            self.exemptions[key] = value
        elif kind == 1:
            assert s.config.flags.native & 128 != 0
            self.pools[key] = value
        else:
            assert kind == 2
            self.limits_exempt[key] = value
        self.refund(floor)

    @arc4.abimethod
    def limits(self, reference: Bytes, asset: Asset, maximum_transaction: UInt64, maximum_wallet: UInt64, cooldown: UInt64, trading_start: UInt64) -> None:
        s = self.authority(reference, asset.id, UInt64(16))
        assert s.config.flags.native & 8 != 0 and cooldown <= 86400
        if maximum_transaction != s.config.maximum_transaction.native or maximum_wallet != s.config.maximum_wallet.native or cooldown != s.config.cooldown.native:
            assert s.config.flags.native & 256 != 0
        if trading_start != s.config.trading_start.native:
            assert s.config.flags.native & 512 != 0
        s.config.maximum_transaction = arc4.UInt64(maximum_transaction)
        s.config.maximum_wallet = arc4.UInt64(maximum_wallet)
        s.config.cooldown = arc4.UInt64(cooldown)
        s.config.trading_start = arc4.UInt64(trading_start)
        self.tokens[reference] = s.copy()

    @arc4.abimethod
    def approve(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, spender: Account, amount: UInt64) -> None:
        floor = self.funded(funding)
        assert self.tokens[reference].asset.native == asset.id
        assert self.tokens[reference].config.flags.native & 8 != 0 and spender != Global.zero_address
        key = op.sha256(reference + Txn.sender.bytes + spender.bytes)
        self.allowances[key] = amount
        self.refund(floor)

    @arc4.abimethod
    def transfer(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, sender: Account, recipient: Account, amount: UInt64) -> None:
        floor = self.funded(funding)
        ensure_budget(3000, fee_source=OpUpFeeSource.GroupCredit)
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id
        assert s.config.flags.native & 8 != 0 and not s.paused.native and amount > 0
        assert sender != Global.current_application_address and recipient != Global.current_application_address and recipient != Global.zero_address
        # Default-frozen smart assets intentionally use clawback; blocklist is an app box,
        # not the native frozen bit which is set for every newly opted-in Smart ASA holder.
        assert not self.pools.get(Bytes(b"blocked") + self.key(reference, sender), default=False)
        assert not self.pools.get(Bytes(b"blocked") + self.key(reference, recipient), default=False)
        if sender != Txn.sender:
            allowance_key = op.sha256(reference + sender.bytes + Txn.sender.bytes)
            self.allowances[allowance_key] = self.allowances.get(allowance_key, default=UInt64(0)) - amount
        exempt = self.exemptions.get(self.key(reference, sender), default=False) or self.exemptions.get(self.key(reference, recipient), default=False)
        rate = s.config.transfer_bps.native
        if self.pools.get(self.key(reference, sender), default=False):
            rate = s.config.buy_bps.native
        elif self.pools.get(self.key(reference, recipient), default=False):
            rate = s.config.sell_bps.native
        high, low = op.mulw(amount, rate)
        tax_amount = UInt64(0) if exempt else op.divw(high, low, 10000)
        free_limits = self.limits_exempt.get(self.key(reference, sender), default=False) or self.limits_exempt.get(self.key(reference, recipient), default=False)
        if not free_limits:
            assert Global.latest_timestamp >= s.config.trading_start.native
            if s.config.maximum_transaction.native:
                assert amount <= s.config.maximum_transaction.native
            if s.config.cooldown.native:
                k = self.key(reference, sender)
                assert Global.latest_timestamp >= self.last_transfer.get(k, default=UInt64(0)) + s.config.cooldown.native
                self.last_transfer[k] = Global.latest_timestamp
        assert asset.balance(sender) >= amount
        self.wallet_limit(reference, s.config.copy(), asset, sender, recipient, amount, tax_amount, recipient)
        for n in urange(s.config.tax_recipients.length):
            self.wallet_limit(reference, s.config.copy(), asset, sender, recipient, amount, tax_amount, s.config.tax_recipients[n].native)
        if tax_amount:
            assigned = UInt64(0)
            for n in urange(s.config.tax_recipients.length):
                part = tax_amount - assigned if n + 1 == s.config.tax_recipients.length else self.portion(tax_amount, s.config.tax_shares[n].native)
                assigned += part
                if part:
                    self.move_votes(reference, s.config.flags.native, sender, s.config.tax_recipients[n].native, part)
                    itxn.AssetTransfer(xfer_asset=asset, asset_sender=sender, asset_receiver=s.config.tax_recipients[n].native, asset_amount=part, fee=0).submit()
        self.move_votes(reference, s.config.flags.native, sender, recipient, amount-tax_amount)
        itxn.AssetTransfer(xfer_asset=asset, asset_sender=sender, asset_receiver=recipient, asset_amount=amount-tax_amount, fee=0).submit()
        self.refund(floor)

    @arc4.abimethod
    def blocklist(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, account: Account, blocked: bool) -> None:
        floor = self.funded(funding)
        s = self.authority(reference, asset.id, UInt64(4))
        assert s.config.flags.native & 8 != 0 and account != Global.current_application_address
        assert s.config.flags.native & 4 != 0
        key = Bytes(b"blocked") + self.key(reference, account)
        previous = self.pools.get(key, default=False)
        if previous != blocked:
            s.frozen_count = arc4.UInt64(s.frozen_count.native + 1 if blocked else s.frozen_count.native - 1)
        self.pools[key] = blocked
        self.tokens[reference] = s.copy()
        self.refund(floor)

    @subroutine
    def wallet_limit(self, reference: Bytes, config: TokenConfig, asset: Asset, sender: Account,
                     recipient: Account, amount: UInt64, tax_amount: UInt64, account: Account) -> None:
        maximum = config.maximum_wallet.native
        if maximum and not self.limits_exempt.get(self.key(reference, account), default=False):
            balance = asset.balance(account)
            if account == sender:
                balance -= amount
            if account == recipient:
                balance += amount - tax_amount
            assigned = UInt64(0)
            for n in urange(config.tax_recipients.length):
                part = tax_amount - assigned if n + 1 == config.tax_recipients.length else self.portion(tax_amount, config.tax_shares[n].native)
                assigned += part
                if config.tax_recipients[n].native == account:
                    balance += part
            assert balance <= maximum

    @subroutine
    def move_votes(self, reference: Bytes, flags: UInt64, sender: Account, recipient: Account, amount: UInt64) -> None:
        if flags & 2048 != 0 and sender != recipient and amount:
            if sender != Global.zero_address:
                delegate = self.delegates.get(self.key(reference, sender), default=sender)
                k = self.key(reference, delegate)
                self.weights[k] = self.weights.get(k, default=UInt64(0)) - amount
            if recipient != Global.zero_address:
                delegate = self.delegates.get(self.key(reference, recipient), default=recipient)
                k = self.key(reference, delegate)
                self.weights[k] = self.weights.get(k, default=UInt64(0)) + amount

    @arc4.abimethod
    def delegate_votes(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, delegate: Account) -> None:
        floor = self.funded(funding)
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id and s.config.flags.native & 2048 != 0
        assert delegate != Global.zero_address
        key = self.key(reference, Txn.sender)
        previous = self.delegates.get(key, default=Txn.sender)
        if previous != delegate:
            amount = asset.balance(Txn.sender)
            old = self.key(reference, previous)
            new = self.key(reference, delegate)
            self.weights[old] = self.weights.get(old, default=UInt64(0)) - amount
            self.weights[new] = self.weights.get(new, default=UInt64(0)) + amount
            self.delegates[key] = delegate
        self.refund(floor)

    @arc4.abimethod(readonly=True)
    def votes(self, reference: Bytes, delegate: Account) -> UInt64:
        return self.weights.get(self.key(reference, delegate), default=UInt64(0))

    @arc4.abimethod
    def revoke_freeze(self, reference: Bytes, asset: Asset) -> None:
        s = self.authority(reference, asset.id, UInt64(4))
        assert Txn.sender == s.owner.native and s.frozen_count.native == 0
        s.config.flags = arc4.UInt64(s.config.flags.native & ~UInt64(4))
        self.tokens[reference] = s.copy()
        itxn.AssetConfig(config_asset=asset, manager=Global.current_application_address,
            reserve=asset.reserve, freeze=Global.current_application_address if s.config.flags.native & 8 != 0 else Global.zero_address, clawback=asset.clawback, fee=0).submit()

    @arc4.abimethod
    def destroy(self, reference: Bytes, asset: Asset) -> None:
        s = self.authority(reference, asset.id, UInt64(1))
        assert Txn.sender == s.owner.native and Txn.sender == s.creator.native
        reserve = asset.balance(Global.current_application_address)
        assert asset.balance(Txn.sender) + reserve == asset.total
        if s.config.flags.native & 8 != 0:
            itxn.AssetFreeze(freeze_asset=asset, freeze_account=Global.current_application_address, frozen=False, fee=0).submit()
            itxn.AssetFreeze(freeze_asset=asset, freeze_account=Txn.sender, frozen=False, fee=0).submit()
        if reserve:
            if s.config.flags.native & 8 != 0:
                itxn.AssetTransfer(xfer_asset=asset, asset_receiver=Txn.sender, asset_amount=reserve,
                    asset_sender=Global.current_application_address, fee=0).submit()
            else:
                itxn.AssetTransfer(xfer_asset=asset, asset_receiver=Txn.sender, asset_amount=reserve, fee=0).submit()
        previous = Global.current_application_address.min_balance
        itxn.AssetTransfer(xfer_asset=asset, asset_receiver=Txn.sender, asset_amount=0, asset_close_to=Txn.sender, fee=0).submit()
        itxn.AssetConfig(config_asset=asset, fee=0).submit()
        s.config.flags = arc4.UInt64(65536)
        s.circulating = arc4.UInt64(0)
        self.tokens[reference] = s.copy()
        released = previous - Global.current_application_address.min_balance
        itxn.Payment(receiver=s.creator.native, amount=released, fee=0).submit()

    @arc4.abimethod
    def clawback(self, funding: gtxn.PaymentTransaction, reference: Bytes, asset: Asset, sender: Account, recipient: Account, amount: UInt64) -> None:
        floor = self.funded(funding)
        s = self.authority(reference, asset.id, UInt64(32))
        assert s.config.flags.native & 8192 != 0 and amount > 0
        assert sender != Global.current_application_address and recipient != Global.current_application_address and recipient != Global.zero_address
        self.move_votes(reference, s.config.flags.native, sender, recipient, amount)
        itxn.AssetTransfer(xfer_asset=asset, asset_sender=sender, asset_receiver=recipient, asset_amount=amount, fee=0).submit()
        self.refund(floor)

    @arc4.abimethod
    def opt_out(self, reference: Bytes, asset: Asset) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id and s.config.flags.native & 8 != 0
        assert Txn.rekey_to == Global.zero_address and asset.balance(Txn.sender) == 0
        assert Txn.group_index + 2 == Global.group_size
        close = gtxn.AssetTransferTransaction(Txn.group_index + 1)
        assert close.type == 4 and close.sender == Txn.sender and close.xfer_asset == asset
        assert close.asset_amount == 0 and close.asset_receiver == s.creator.native and close.asset_close_to == s.creator.native
        assert close.asset_sender == Global.zero_address and close.rekey_to == Global.zero_address
        itxn.AssetFreeze(freeze_asset=asset, freeze_account=Txn.sender, frozen=False, fee=0).submit()

    @arc4.abimethod
    def detach(self, reference: Bytes, asset: Asset) -> None:
        s = self.tokens[reference].copy()
        assert s.asset.native == asset.id and Txn.sender == s.owner.native
        assert Txn.rekey_to == Global.zero_address and s.config.flags.native & 8 == 0
        assert not s.paused.native and s.frozen_count.native == 0
        s.owner = arc4.Address()
        s.pending = arc4.Address()
        s.config.flags = arc4.UInt64(s.config.flags.native & UInt64(18))
        self.tokens[reference] = s.copy()
        itxn.AssetConfig(config_asset=asset, manager=Global.zero_address, reserve=asset.reserve,
            freeze=Global.zero_address, clawback=Global.zero_address, fee=0).submit()

    @arc4.abimethod(readonly=True)
    def token(self, reference: Bytes) -> TokenState:
        return self.tokens[reference].copy()
