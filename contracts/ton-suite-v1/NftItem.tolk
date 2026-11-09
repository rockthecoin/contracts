tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"
import "payments"

type NftMessage = LaunchCreation | AskToChangeOwnership | RequestStaticData | RetrySettlement | RefundExcess | InitializeItem | SetMetadata | FreezeMetadata | BurnItem | TopUpTons
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg=lazy ServicePayment.fromSlice(in.bouncedBody);
    var s=lazy NftStorage.load();val c=s.config.load();
    assert(s.phase==2 && in.senderAddress==c.treasury && msg.queryId==queryIdFor(c)) throw 710;
    s.phase=4;s.save();
}
fun onInternalMessage(in: InMessage) {
    if(in.body.isEmpty()) {return;}
    val msg=lazy NftMessage.fromSlice(in.body);
    var s=lazy NftStorage.load();val c=s.config.load();val e=c.economics.load();
    match(msg) {
        LaunchCreation => {
            requireQuery(c,msg.queryId);
            assert(s.phase==0 && s.details.load().collection==null && in.senderAddress==c.identity.load().launcher) throw 711;
            if(blockchain.now()>c.deadline) {s.phase=3;s.save();refundAllToCreator(c);return;}
            assert(in.valueCoins>=e.minimumLaunchValue && e.initialSupply==1) throw 705;
            var r = s.receipts.load();r.launchLt = in.createdLt;s.receipts = r.toCell();
            s.receipts = settlementReceipt(s.receipts, in.senderAddress, in.createdLt, e.serviceFee);
            s.phase=2;s.ownerAddress=c.creator;s.save();payServiceAndRefund(c);
        }
        AskToChangeOwnership => {
            assert((s.phase==2||s.phase==4) && in.senderAddress==s.ownerAddress && msg.newOwnerAddress.getWorkchain()==0) throw 707;
            checkForwardPayload(msg.forwardPayload);
            assert(in.valueCoins>msg.forwardTonAmount+calculateGasFee(0,25000)+in.originalForwardFee*3) throw 705;
            s.ownerAddress=msg.newOwnerAddress;s.save();
            reserveGramsOnBalance(max(e.storageReserve,contract.getOriginalBalance()-in.valueCoins),RESERVE_MODE_AT_MOST);
            if(msg.forwardTonAmount>0) {
                val notify=createMessage({bounce:BounceMode.NoBounce,dest:msg.newOwnerAddress,value:msg.forwardTonAmount,body:NotificationForNewOwner {queryId:msg.queryId,oldOwnerAddress:in.senderAddress,forwardPayload:msg.forwardPayload}});
                notify.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
            if(msg.sendExcessesTo!=null) {
                val excess=createMessage({bounce:BounceMode.NoBounce,dest:msg.sendExcessesTo,value:0,body:ReturnExcessesBack {queryId:msg.queryId}});
                excess.send(SEND_MODE_CARRY_ALL_BALANCE|SEND_MODE_IGNORE_ERRORS);
            }
        }
        RequestStaticData => {
            val reply=createMessage({bounce:BounceMode.NoBounce,dest:in.senderAddress,value:0,body:ResponseStaticData {queryId:msg.queryId,itemIndex:s.details.load().index as uint256,collectionAddress:s.details.load().collection}});
            reply.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        RetrySettlement => {
            requireQuery(c,msg.queryId);
            assert(s.phase==4 && in.valueCoins>=mintReceiptValue()+calculateGasFee(0,25000)) throw 712;
            s.receipts = settlementReceipt(s.receipts, in.senderAddress, in.createdLt, e.serviceFee);
            s.phase=2;s.save();payServiceAndRefund(c);
        }
        RefundExcess => {requireQuery(c,msg.queryId);assert(s.phase==2) throw 712;refundExcessToCreator(c,in.valueCoins);}
        InitializeItem => {
            var d=s.details.load();assert(d.collection!=null && in.senderAddress==d.collection!) throw 710;
            val newlyCreated=s.phase==0;
            if(s.phase==0){s.phase=2;s.ownerAddress=msg.owner;s.content=msg.content;d.metadataAuthority=msg.authority;d.mutable=msg.mutable;s.details=d.toCell();s.save();}
            else{assert(s.phase==2 && d.mutable && msg.authority!=null && msg.authority! == in.senderAddress) throw 724;s.content=msg.content;d.mutable=msg.mutable;s.details=d.toCell();s.save();}
            reserveGramsOnBalance(max(grams("0.03"),calculateStorageFee(0,5*365*86400,16000,64)),RESERVE_MODE_EXACT_AMOUNT);
            val ack=createMessage({bounce:BounceMode.NoBounce,dest:in.senderAddress,value:grams("0.015"),body:FactoryReceipt{queryId:msg.queryId}});ack.send(SEND_MODE_PAY_FEES_SEPARATELY);
            val excess=createMessage({bounce:BounceMode.NoBounce,dest:s.ownerAddress,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});excess.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
        }
        SetMetadata => {val d=s.details.load();assert(s.phase==2 && d.mutable && d.metadataAuthority!=null && in.senderAddress==d.metadataAuthority!) throw 710;s.content=msg.content;s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        FreezeMetadata => {var d=s.details.load();assert(s.phase==2 && d.metadataAuthority!=null && in.senderAddress==d.metadataAuthority!) throw 710;d.mutable=false;d.metadataAuthority=null;s.details=d.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        BurnItem => {assert(s.phase==2 && in.senderAddress==s.ownerAddress && s.details.load().burnable) throw 710;s.phase=5;s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        TopUpTons => {}
        else => throw 703
    }
}
get fun get_nft_data(): (bool,int,address?,address?,cell) {
    val s=lazy NftStorage.load();val d=s.details.load();return(s.phase==2||s.phase==4,d.index,d.collection,s.phase==0||s.phase==3||s.phase==5?null:s.ownerAddress,s.content);
}
get fun get_creation_state(): (int,int,int) {
    val s=lazy NftStorage.load();val c=s.config.load();return(s.phase,c.quoteId,1);
}
