tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"
import "payments"

struct EscrowTerms {
    kind: uint8 // 0 TON, 1 jetton, 2 NFT; 3 jetton time lock
    beneficiary: address
    asset: address?
    start: uint32
    cliff: uint32
    end: uint32
    principal: coins
}
struct EscrowStorage {
    phase: uint8 // 0 new, 1 awaiting asset, 2 funded, 3 cancelled, 4 fee bounced
    claimed: coins
    wallet: address?
    config: Cell<CreationConfig>
    terms: Cell<EscrowTerms>
    receipts: Cell<CreationReceipts>
}
type EscrowMessage = LaunchCreation | TransferNotificationForRecipient | NotificationForNewOwner | ReleaseEscrow | ReleaseSurplus | CancelUnfunded | RetrySettlement | ReturnExcessesBack | ResponseWalletAddress | TopUpTons
type EscrowBounce = AskToTransfer | AskToChangeOwnership | ServicePayment
fun onBouncedMessage(in:InMessageBounced){
    in.bouncedBody.skipBouncedPrefix();val msg=lazy EscrowBounce.fromSlice(in.bouncedBody);
    var s=EscrowStorage.fromCell(contract.getData());val t=s.terms.load();val c=s.config.load();
    match(msg){
        AskToTransfer=>{assert(s.wallet!=null && in.senderAddress==s.wallet! && msg.jettonAmount<=s.claimed) throw 710;s.claimed-=msg.jettonAmount;contract.setData(s.toCell());}
        AskToChangeOwnership=>{assert(t.asset!=null && in.senderAddress==t.asset! && t.kind==2 && s.claimed==1) throw 710;s.claimed=0;contract.setData(s.toCell());}
        ServicePayment=>{assert(s.phase==2 && in.senderAddress==c.treasury && msg.queryId==queryIdFor(c)) throw 710;s.phase=4;contract.setData(s.toCell());}
        else=>throw 703
    }
}
fun escrowPayment(s:EscrowStorage){
    val c=s.config.load();val t=s.terms.load();val e=c.economics.load();
    reserveGramsOnBalance(e.storageReserve+(t.kind==0?t.principal-s.claimed:0 as coins),RESERVE_MODE_EXACT_AMOUNT);
    if(e.serviceFee>0){val fee=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:c.treasury,value:e.serviceFee+e.recipientTopup,body:ServicePayment{queryId:queryIdFor(c),quoteId:c.quoteId}});fee.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
    val ack=createMessage({bounce:BounceMode.NoBounce,dest:c.identity.load().launcher,value:grams("0.015"),body:FactoryReceipt{queryId:queryIdFor(c)}});ack.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
    val refund=createMessage({bounce:BounceMode.NoBounce,dest:c.creator,value:0,body:ReturnExcessesBack{queryId:queryIdFor(c)}});refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
}
fun onInternalMessage(in:InMessage){
    if(in.body.isEmpty()){return;}val msg=lazy EscrowMessage.fromSlice(in.body);
    var s=EscrowStorage.fromCell(contract.getData());val c=s.config.load();val t=s.terms.load();val e=c.economics.load();
    match(msg){
        LaunchCreation=>{
            requireQuery(c,msg.queryId);assert(s.phase==0 && in.senderAddress==c.identity.load().launcher) throw 710;
            if(blockchain.now()>c.deadline){s.phase=3;contract.setData(s.toCell());refundAllToCreator(c);return;}
            assert(t.end>=t.cliff && t.cliff>=t.start && t.end>t.start && t.principal>0 && t.beneficiary.getWorkchain()==0 && in.valueCoins>=e.minimumLaunchValue+(t.kind==0?t.principal:0 as coins)) throw 705;
            var r=s.receipts.load();r.launchLt=in.createdLt;s.receipts=r.toCell();s.phase=t.kind==0?2:1;
            if(t.kind==0){s.receipts=settlementReceipt(s.receipts,in.senderAddress,in.createdLt,e.serviceFee);}
            contract.setData(s.toCell());if(t.kind==0){escrowPayment(s);}else if(t.kind==1||t.kind==3){
                assert(t.asset!=null) throw 724;
                val discover=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:t.asset!,value:grams("0.05"),body:RequestWalletAddress{queryId:queryIdFor(c),ownerAddress:contract.getAddress(),includeOwnerAddress:true}});discover.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            }
        }
        ResponseWalletAddress=>{
            assert(s.phase==1 && t.asset!=null && in.senderAddress==t.asset! && msg.queryId==queryIdFor(c) && msg.jettonWalletAddress!=null && msg.ownerAddress!=null && msg.ownerAddress!.load()==contract.getAddress()) throw 710;
            s.wallet=msg.jettonWalletAddress;contract.setData(s.toCell());
        }
        TransferNotificationForRecipient=>{
            if(s.phase==3){
                assert(s.wallet!=null && in.senderAddress==s.wallet! && msg.transferInitiator!=null && msg.transferInitiator! == c.creator && in.valueCoins>=grams("0.15")) throw 710;
                val back=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:s.wallet!,value:grams("0.1"),body:AskToTransfer{queryId:msg.queryId,jettonAmount:msg.jettonAmount,transferRecipient:c.creator,sendExcessesTo:c.creator,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});back.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);return;
            }
            assert(s.phase==1 && (t.kind==1||t.kind==3) && s.wallet!=null && in.senderAddress==s.wallet! && msg.transferInitiator!=null && msg.transferInitiator! == c.creator && msg.queryId==queryIdFor(c) && msg.jettonAmount==t.principal) throw 710;
            assert(in.valueCoins>=grams("0.08")) throw 705;s.phase=2;s.receipts=settlementReceipt(s.receipts,in.senderAddress,in.createdLt,e.serviceFee);contract.setData(s.toCell());escrowPayment(s);
        }
        NotificationForNewOwner=>{
            if(s.phase==3){
                assert(t.kind==2 && t.asset!=null && in.senderAddress==t.asset! && msg.oldOwnerAddress==c.creator && in.valueCoins>=grams("0.15")) throw 710;
                val back=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:t.asset!,value:grams("0.1"),body:AskToChangeOwnership{queryId:msg.queryId,newOwnerAddress:c.creator,sendExcessesTo:c.creator,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});back.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);return;
            }
            assert(s.phase==1 && t.kind==2 && t.asset!=null && in.senderAddress==t.asset! && msg.oldOwnerAddress==c.creator && msg.queryId==queryIdFor(c) && in.valueCoins>=grams("0.08")) throw 710;
            s.phase=2;s.receipts=settlementReceipt(s.receipts,in.senderAddress,in.createdLt,e.serviceFee);contract.setData(s.toCell());escrowPayment(s);
        }
        ReleaseEscrow=>{
            if(s.phase==3){
                assert(t.kind==2 && t.asset!=null && in.senderAddress==c.creator && in.valueCoins>=grams("0.15")) throw 710;
                val recover=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:t.asset!,value:grams("0.1"),body:AskToChangeOwnership{queryId:msg.queryId,newOwnerAddress:c.creator,sendExcessesTo:c.creator,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});recover.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);return;
            }
            assert(s.phase==2 && blockchain.now()>=t.cliff && in.valueCoins>=grams("0.15")) throw 724;
            var vested:coins=blockchain.now()>=t.end?t.principal:(t.kind==2||t.kind==3?0 as coins:(t.principal*(blockchain.now()-t.start)/(t.end-t.start)) as coins);
            assert(vested>s.claimed) throw 724;val amount=vested-s.claimed;s.claimed=vested;contract.setData(s.toCell());
            reserveGramsOnBalance(max(e.storageReserve+(t.kind==0?t.principal-s.claimed:0 as coins),contract.getOriginalBalance()-in.valueCoins-(t.kind==0?amount:0 as coins)),RESERVE_MODE_EXACT_AMOUNT);
            if(t.kind==0){val release=createMessage({bounce:BounceMode.NoBounce,dest:t.beneficiary,value:amount,body:ReturnExcessesBack{queryId:msg.queryId}});release.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
            else if(t.kind==2){val release=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:t.asset!,value:grams("0.1"),body:AskToChangeOwnership{queryId:msg.queryId,newOwnerAddress:t.beneficiary,sendExcessesTo:t.beneficiary,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});release.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
            else{val release=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:s.wallet!,value:grams("0.1"),body:AskToTransfer{queryId:msg.queryId,jettonAmount:amount,transferRecipient:t.beneficiary,sendExcessesTo:t.beneficiary,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});release.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
            val excess=createMessage({bounce:BounceMode.NoBounce,dest:in.senderAddress,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});excess.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
        }
        ReleaseSurplus=>{
            if(s.phase==3){
                if(msg.amount==0){assert(in.senderAddress==c.creator && in.valueCoins>=grams("0.05")) throw 710;reserveGramsOnBalance(e.storageReserve,RESERVE_MODE_EXACT_AMOUNT);val nativeRefund=createMessage({bounce:BounceMode.NoBounce,dest:c.creator,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});nativeRefund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);return;}
                assert((t.kind==1||t.kind==3) && s.wallet!=null && in.senderAddress==c.creator && msg.amount>0 && in.valueCoins>=grams("0.15")) throw 710;
                val recover=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:s.wallet!,value:grams("0.1"),body:AskToTransfer{queryId:msg.queryId,jettonAmount:msg.amount,transferRecipient:c.creator,sendExcessesTo:c.creator,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});recover.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);return;
            }
            // External jetton wallets can return a failed downstream transfer to
            // the escrow wallet. Only the beneficiary may recover it, after all
            // principal has vested; never trust a supplied balance before end.
            assert(s.phase==2 && blockchain.now()>=t.end && in.senderAddress==t.beneficiary && in.valueCoins>=grams("0.15")) throw 710;
            if(t.kind==0||msg.amount==0){if(t.kind==0){s.claimed=t.principal;contract.setData(s.toCell());}reserveGramsOnBalance(e.storageReserve,RESERVE_MODE_EXACT_AMOUNT);val surplus=createMessage({bounce:BounceMode.NoBounce,dest:t.beneficiary,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});surplus.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
            else{assert(t.kind!=2 && msg.amount>0) throw 724;val surplus=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:s.wallet!,value:grams("0.1"),body:AskToTransfer{queryId:msg.queryId,jettonAmount:msg.amount,transferRecipient:t.beneficiary,sendExcessesTo:t.beneficiary,customPayload:null,forwardTonAmount:1,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});surplus.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);}
        }
        CancelUnfunded=>{assert(s.phase==1 && in.senderAddress==c.creator && blockchain.now()>c.deadline) throw 710;s.phase=3;contract.setData(s.toCell());
            reserveGramsOnBalance(e.storageReserve,RESERVE_MODE_EXACT_AMOUNT);
            val ack=createMessage({bounce:BounceMode.NoBounce,dest:c.identity.load().launcher,value:grams("0.015"),body:FactoryReceipt{queryId:queryIdFor(c)}});ack.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
            val refund=createMessage({bounce:BounceMode.NoBounce,dest:c.creator,value:0,body:ReturnExcessesBack{queryId:queryIdFor(c)}});refund.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
        }
        RetrySettlement=>{requireQuery(c,msg.queryId);assert(s.phase==4 && in.valueCoins>=grams("0.1")) throw 712;s.phase=2;s.receipts=settlementReceipt(s.receipts,in.senderAddress,in.createdLt,e.serviceFee);contract.setData(s.toCell());escrowPayment(s);}
        ReturnExcessesBack=>{}
        TopUpTons=>{}
        else=>throw 703
    }
}
get fun get_escrow_data():cell{return contract.getData();}
