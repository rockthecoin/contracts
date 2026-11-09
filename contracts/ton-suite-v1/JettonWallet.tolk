tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"
import "payments"

// TEP-74 wallet. A master-origin mint credits the supply and emits a mandatory
// standard Excesses receipt in the SAME wallet transaction. Failure to emit it
// rolls the credit back. Ordinary transfers/burns keep standard behavior.
type WalletMessage = AskToTransfer | InternalTransferStep | AskToBurn | RetryMintReceipt | SetWalletFrozen | TopUpTons
type WalletBounce = InternalTransferStep | BurnNotificationForMinter | ReturnExcessesBack
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy WalletBounce.fromSlice(in.bouncedBody);
    var s = lazy WalletStorage.load();
    match (msg) {
        InternalTransferStep => { s.jettonBalance += msg.jettonAmount; s.save(); }
        BurnNotificationForMinter => { assert (in.senderAddress == s.minterAddress) throw 702; s.jettonBalance += msg.jettonAmount; s.save(); }
        ReturnExcessesBack => { assert (in.senderAddress == s.minterAddress && msg.queryId == s.mintQueryId) throw 702; }
        else => throw 703
    }
}
fun sendMintReceipt(s: WalletStorage) {
    reserveGramsOnBalance(walletStorageReserve(), RESERVE_MODE_EXACT_AMOUNT);
    val receipt = createMessage({bounce: BounceMode.Only256BitsOfBody, dest: s.minterAddress, value: mintReceiptValue(), body: ReturnExcessesBack {queryId: s.mintQueryId}});
    receipt.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
    val unused = createMessage({bounce: BounceMode.NoBounce, dest: s.ownerAddress, value: 0, body: ReturnExcessesBack {queryId: s.mintQueryId}});
    unused.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) { return; }
    val msg = lazy WalletMessage.fromSlice(in.body);
    var s = lazy WalletStorage.load();
    match (msg) {
        InternalTransferStep => {
            checkForwardPayload(msg.forwardPayload);
            if (in.senderAddress == s.minterAddress) {
                assert (msg.jettonAmount > 0 && msg.forwardTonAmount == 0 && msg.sendExcessesTo != null) throw 704;
                assert (in.valueCoins >= requiredMintValue()) throw 705;
                s.jettonBalance += msg.jettonAmount;
                if(s.mintedAmount==0){s.mintQueryId=msg.queryId;s.mintedAmount=msg.jettonAmount;}
                s.save();
                reserveGramsOnBalance(walletStorageReserve(),RESERVE_MODE_EXACT_AMOUNT);
                val ack=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:s.minterAddress,value:mintReceiptValue(),body:ReturnExcessesBack{queryId:msg.queryId}});
                ack.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
                val unused=createMessage({bounce:BounceMode.NoBounce,dest:s.ownerAddress,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});
                unused.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
                return;
            }
            assert (msg.transferInitiator != null && in.senderAddress == walletAddress(msg.transferInitiator!, s.minterAddress, contract.getCode())) throw 706;
            s.jettonBalance += msg.jettonAmount;
            s.save();
            if (msg.forwardTonAmount > 0) {
                val notify = createMessage({bounce: BounceMode.NoBounce, dest: s.ownerAddress, value: msg.forwardTonAmount, body: TransferNotificationForRecipient {queryId: msg.queryId, jettonAmount: msg.jettonAmount, transferInitiator: msg.transferInitiator, forwardPayload: msg.forwardPayload}});
                notify.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            }
            if (msg.sendExcessesTo != null) {
                reserveGramsOnBalance(max(walletStorageReserve(), contract.getOriginalBalance() - in.valueCoins + contract.getStorageDuePayment()), RESERVE_MODE_AT_MOST);
                val excess = createMessage({bounce: BounceMode.NoBounce, dest: msg.sendExcessesTo, value: 0, body: ReturnExcessesBack {queryId: msg.queryId}});
                excess.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
            }
        }
        AskToTransfer => {
            assert (!s.frozen && in.senderAddress == s.ownerAddress && msg.transferRecipient.getWorkchain() == 0) throw 707;
            checkForwardPayload(msg.forwardPayload);
            assert (msg.jettonAmount > 0 && s.jettonBalance >= msg.jettonAmount) throw 708;
            val minValue = walletStorageReserve() + calculateGasFee(0, 50000) + calculateForwardFee(0, 30000, 128) * 3 + msg.forwardTonAmount;
            assert (in.valueCoins > minValue) throw 705;
            s.jettonBalance -= msg.jettonAmount;
            s.save();
            val transfer = createMessage({bounce: BounceMode.Only256BitsOfBody, dest: deployedWallet(msg.transferRecipient, s.minterAddress, contract.getCode()), value: 0, body: InternalTransferStep {queryId: msg.queryId, jettonAmount: msg.jettonAmount, transferInitiator: s.ownerAddress, sendExcessesTo: msg.sendExcessesTo, forwardTonAmount: msg.forwardTonAmount, forwardPayload: msg.forwardPayload}});
            transfer.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        AskToBurn => {
            assert (in.senderAddress == s.ownerAddress) throw 707;
            assert (msg.jettonAmount > 0 && s.jettonBalance >= msg.jettonAmount) throw 708;
            assert (in.valueCoins > calculateGasFee(0, 50000) + calculateForwardFee(0, 2000, 8)) throw 705;
            s.jettonBalance -= msg.jettonAmount;
            s.save();
            val burn = createMessage({bounce: BounceMode.Only256BitsOfBody, dest: s.minterAddress, value: 0, body: BurnNotificationForMinter {queryId: msg.queryId, jettonAmount: msg.jettonAmount, burnInitiator: s.ownerAddress, sendExcessesTo: msg.sendExcessesTo}});
            burn.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        RetryMintReceipt => {
            assert (s.mintedAmount > 0 && msg.queryId == s.mintQueryId) throw 709;
            assert (in.valueCoins >= mintReceiptValue() + calculateGasFee(0, 25000)) throw 705;
            sendMintReceipt(s);
        }
        SetWalletFrozen => {assert(in.senderAddress==s.minterAddress) throw 710;s.frozen=msg.frozen;s.save();reserveGramsOnBalance(max(walletStorageReserve(),contract.getOriginalBalance()-in.valueCoins+contract.getStorageDuePayment()),RESERVE_MODE_AT_MOST);val refund=createMessage({bounce:BounceMode.NoBounce,dest:msg.response,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);}
        TopUpTons => {}
        else => throw 703
    }
}
get fun get_wallet_data(): (int, address, address, cell) {
    val s = lazy WalletStorage.load();
    return (s.jettonBalance, s.ownerAddress, s.minterAddress, contract.getCode());
}
get fun get_mint_receipt(): (int, int) {
    val s = lazy WalletStorage.load();return (s.mintQueryId, s.mintedAmount);
}

get fun get_wallet_frozen():bool{return WalletStorage.load().frozen;}
