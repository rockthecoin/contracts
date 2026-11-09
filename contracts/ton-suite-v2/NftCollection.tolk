tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"
import "payments"

type CollectionMessage = LaunchCreation | MintItem | FactoryReceipt | SetPause | CloseMinting | SetMetadata | FreezeMetadata | EditItem | SetRoyalty | FreezeRoyalty | RequestRoyalty | ProposeOwner | AcceptOwner | RenounceOwner | SetRole | RetrySettlement | TopUpTons
type CollectionBounce = ServicePayment | InitializeItem | SetItemMetadata
fun onBouncedMessage(in:InMessageBounced){
    in.bouncedBody.skipBouncedPrefix();val msg=lazy CollectionBounce.fromSlice(in.bouncedBody);
    var s=CollectionStorage.load();val c=s.config.load();
    match(msg){
        ServicePayment=>{assert(s.phase==2 && in.senderAddress==c.treasury && msg.queryId==queryIdFor(c)) throw 710;s.phase=4;s.save();}
        InitializeItem=>{val ctl=s.controls.load();val p=ctl.pending.mustGet(msg.queryId,710);assert(in.senderAddress==collectionItem(p.index,contract.getAddress(),s.config,ctl.itemCode).calculateAddress()) throw 710;val refund=createMessage({bounce:BounceMode.NoBounce,dest:p.requester,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});refund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);}
        SetItemMetadata=>{var ctl=s.controls.load();val p=ctl.pending.mustGet(msg.queryId,710);assert(in.senderAddress==collectionItem(p.index,contract.getAddress(),s.config,ctl.itemCode).calculateAddress()) throw 710;ctl.pending.delete(msg.queryId);s.controls=ctl.toCell();s.save();val refund=createMessage({bounce:BounceMode.NoBounce,dest:p.requester,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});refund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);}
        else=>throw 703
    }
}
fun owner(ctl:CollectionControls,sender:address){assert(ctl.owner!=null && sender==ctl.owner!) throw 710;assert(CollectionStorage.load().phase==2||CollectionStorage.load().phase==4) throw 711;}
fun role(ctl:CollectionControls,sender:address,bit:int){assert(CollectionStorage.load().phase==2||CollectionStorage.load().phase==4) throw 711;if(ctl.owner!=null && sender==ctl.owner!){return;}val r=ctl.roles.get(sender);assert(ctl.owner!=null && r.isFound && (r.loadValue() & bit)!=0) throw 710;}
fun onInternalMessage(in:InMessage){
    if(in.body.isEmpty()){return;}val msg=lazy CollectionMessage.fromSlice(in.body);
    var s=CollectionStorage.load();val c=s.config.load();var ctl=s.controls.load();
    match(msg){
        LaunchCreation=>{
            requireQuery(c,msg.queryId);assert(s.phase==0 && in.senderAddress==c.identity.load().launcher) throw 710;
            if(blockchain.now()>c.deadline){s.phase=3;s.save();refundAllToCreator(c);return;}
            assert(in.valueCoins>=c.economics.load().minimumLaunchValue && ctl.maximum>0 && ctl.royaltyNumerator<=10000) throw 705;
            var r=s.receipts.load();r.launchLt=in.createdLt;s.receipts=settlementReceipt(r.toCell(),in.senderAddress,in.createdLt,c.economics.load().serviceFee);s.phase=2;s.save();payServiceAndRefund(c);
        }
        MintItem=>{
            assert(s.phase==2 && ctl.mintable && !ctl.paused && in.valueCoins>=grams("0.15") && msg.recipient.getWorkchain()==0) throw 724;role(ctl,in.senderAddress,1);
            var index=s.nextIndex;
            val existing=ctl.pending.get(msg.queryId);
            if(existing.isFound){val p=existing.loadValue();assert(p.mint && msg.expectedIndex==p.index && p.recipient==msg.recipient && p.content.hash()==msg.content.hash()) throw 723;index=p.index;}
            else{assert(msg.expectedIndex==index) throw 723;assert(index<ctl.maximum && index<18446744073709551615) throw 724;ctl.pending.set(msg.queryId,PendingItem{index,recipient:msg.recipient,requester:in.senderAddress,content:msg.content,mint:true,mutable:ctl.metadataMutable});s.nextIndex+=1;s.controls=ctl.toCell();s.save();}
            val mint=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:collectionItem(index,contract.getAddress(),s.config,ctl.itemCode),value:0,body:InitializeItem{queryId:msg.queryId,owner:msg.recipient,content:msg.content,authority:contract.getAddress(),mutable:ctl.pending.mustGet(msg.queryId,710).mutable}});
            mint.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        FactoryReceipt=>{if(!ctl.pending.exists(msg.queryId)){return;}val p=ctl.pending.mustGet(msg.queryId,710);assert(in.senderAddress==collectionItem(p.index,contract.getAddress(),s.config,ctl.itemCode).calculateAddress()) throw 710;ctl.pending.delete(msg.queryId);s.controls=ctl.toCell();s.save();refundCommandBudget(c,p.requester,in.valueCoins);}
        SetPause=>{role(ctl,in.senderAddress,2);ctl.paused=msg.paused;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        CloseMinting=>{owner(ctl,in.senderAddress);ctl.mintable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        SetMetadata=>{role(ctl,in.senderAddress,4);assert(ctl.metadataMutable) throw 724;s.content=msg.content;s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        FreezeMetadata=>{owner(ctl,in.senderAddress);ctl.metadataMutable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        EditItem=>{
            role(ctl,in.senderAddress,4);assert(ctl.metadataMutable && msg.index<s.nextIndex && in.valueCoins>=grams("0.05")) throw 724;
            assert(!ctl.pending.exists(msg.queryId)) throw 723;ctl.pending.set(msg.queryId,PendingItem{index:msg.index,recipient:in.senderAddress,requester:in.senderAddress,content:msg.content,mint:false,mutable:!msg.freeze});s.controls=ctl.toCell();s.save();
            val change=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:collectionItem(msg.index,contract.getAddress(),s.config,ctl.itemCode).calculateAddress(),value:0,body:SetItemMetadata{queryId:msg.queryId,content:msg.content,mutable:!msg.freeze}});
            change.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        SetRoyalty=>{role(ctl,in.senderAddress,8);assert(ctl.royaltyMutable && msg.numerator<=10000 && msg.recipient.getWorkchain()==0) throw 724;ctl.royaltyNumerator=msg.numerator;ctl.royaltyRecipient=msg.recipient;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        FreezeRoyalty=>{owner(ctl,in.senderAddress);ctl.royaltyMutable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        RequestRoyalty=>{val reply=createMessage({bounce:BounceMode.NoBounce,dest:in.senderAddress,value:0,body:RoyaltyResponse{queryId:msg.queryId,numerator:ctl.royaltyNumerator,denominator:10000,recipient:ctl.royaltyRecipient}});reply.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);}
        ProposeOwner=>{owner(ctl,in.senderAddress);assert(msg.owner.getWorkchain()==0) throw 701;ctl.pendingOwner=msg.owner;s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        AcceptOwner=>{assert(s.phase==2||s.phase==4) throw 711;assert(ctl.pendingOwner!=null && in.senderAddress==ctl.pendingOwner!) throw 710;ctl.owner=in.senderAddress;ctl.pendingOwner=null;ctl.roles=createEmptyMap();s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        RenounceOwner=>{owner(ctl,in.senderAddress);assert(!ctl.paused) throw 724;ctl.owner=null;ctl.pendingOwner=null;ctl.mintable=false;ctl.metadataMutable=false;ctl.royaltyMutable=false;ctl.roles=createEmptyMap();s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        SetRole=>{owner(ctl,in.senderAddress);assert(msg.roles<=15 && msg.account.getWorkchain()==0) throw 724;if(msg.roles==0){ctl.roles.delete(msg.account);}else{ctl.roles.set(msg.account,msg.roles);}s.controls=ctl.toCell();s.save();refundCommandBudget(c,in.senderAddress,in.valueCoins);}
        RetrySettlement=>{requireQuery(c,msg.queryId);assert(s.phase==4 && in.valueCoins>=grams("0.1")) throw 712;s.receipts=settlementReceipt(s.receipts,in.senderAddress,in.createdLt,c.economics.load().serviceFee);s.phase=2;s.save();payServiceAndRefund(c);}
        TopUpTons=>{}
        else=>throw 703
    }
}
get fun get_collection_data():(int,cell,address?){val s=CollectionStorage.load();return(s.nextIndex,s.content,s.controls.load().owner);}
get fun get_nft_address_by_index(index:uint64):address{val s=CollectionStorage.load();return collectionItem(index,contract.getAddress(),s.config,s.controls.load().itemCode).calculateAddress();}
get fun get_nft_content(index:uint64,individual:cell):cell{return individual;}
get fun royalty_params():(int,int,address){val c=CollectionStorage.load().controls.load();return(c.royaltyNumerator,10000,c.royaltyRecipient);}
get fun get_collection_controls():cell{return CollectionStorage.load().controls;}
