tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"

// Conservative execution/storage bounds. Runtime fee primitives read TON's
// current on-chain prices; launch quotes must allocate at least these amounts.
fun walletStorageReserve(): coins {
    return max(grams("0.02"), calculateStorageFee(0, 5 * 365 * 86400, 24000, 96));
}
fun mintReceiptValue(): coins {
    return max(grams("0.015"), calculateGasFee(0, 25000) + calculateForwardFee(0, 2000, 8));
}
fun requiredMintValue(): coins {
    return walletStorageReserve() + mintReceiptValue() + calculateGasFee(0, 25000) + calculateForwardFee(0, 3000, 12);
}
fun queryIdFor(config: CreationConfig): uint64 { return (config.quoteId >> 192) as uint64; }
// These durable message coordinates let the verifier locate exact committed
// receipts without scanning a busy receiving wallet's entire history.
fun settlementReceipt(receipts: Cell<CreationReceipts>, sender: address, incomingLt: uint64, serviceFee: coins): Cell<CreationReceipts> {
    var r = receipts.load();
    r.settlementSender = sender;r.settlementLt = incomingLt;
    r.feeLt = serviceFee > 0 ? blockchain.logicalTime() + 1 : 0;
    return r.toCell();
}
fun requireQuery(config: CreationConfig, queryId: uint64) {
    assert (queryId == queryIdFor(config)) throw 700;
    assert (config.creator.getWorkchain() == 0 && config.treasury.getWorkchain() == 0) throw 701;
}
fun refundAllToCreator(config: CreationConfig) {
    val receipt=createMessage({bounce:BounceMode.NoBounce,dest:config.identity.load().launcher,value:grams("0.015"),body:FactoryReceipt{queryId:queryIdFor(config)}});
    receipt.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
    val refund = createMessage({bounce: BounceMode.NoBounce, dest: config.creator, value: 0, body: ReturnExcessesBack {queryId: queryIdFor(config)}});
    refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
}
fun payServiceAndRefund(config: CreationConfig) {
    val economics = config.economics.load();
    reserveGramsOnBalance(economics.storageReserve, RESERVE_MODE_EXACT_AMOUNT);
    if (economics.serviceFee > 0) {
        val payment = createMessage({bounce: BounceMode.Only256BitsOfBody, dest: config.treasury, value: economics.serviceFee + economics.recipientTopup, body: ServicePayment {queryId: queryIdFor(config), quoteId: config.quoteId}});
        payment.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
    }
    val receipt=createMessage({bounce:BounceMode.NoBounce,dest:config.identity.load().launcher,value:grams("0.015"),body:FactoryReceipt{queryId:queryIdFor(config)}});
    receipt.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
    val refund = createMessage({bounce: BounceMode.NoBounce, dest: config.creator, value: 0, body: ReturnExcessesBack {queryId: queryIdFor(config)}});
    refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
fun refundExcessToCreator(config: CreationConfig, incomingValue: coins) {
    val economics = config.economics.load();
    // Keep the original rent deposit. A third party cannot drain it by replay.
    reserveGramsOnBalance(max(economics.storageReserve, contract.getOriginalBalance() - incomingValue), RESERVE_MODE_AT_MOST);
    val refund = createMessage({bounce: BounceMode.NoBounce, dest: config.creator, value: 0, body: ReturnExcessesBack {queryId: queryIdFor(config)}});
    refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
fun refundCommandBudget(config:CreationConfig,recipient:address,incomingValue:coins){
    reserveGramsOnBalance(max(config.economics.load().storageReserve,contract.getOriginalBalance()-incomingValue+contract.getStorageDuePayment()),RESERVE_MODE_AT_MOST);
    val refund=createMessage({bounce:BounceMode.NoBounce,dest:recipient,value:0,body:ReturnExcessesBack{queryId:queryIdFor(config)}});
    refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
