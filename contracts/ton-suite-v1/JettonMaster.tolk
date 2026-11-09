tolk 1.5
import "@stdlib/gas-payments"
import "messages"
import "storage"
import "payments"

type MasterMessage = LaunchCreation | ReturnExcessesBack | BurnNotificationForMinter | RequestWalletAddress | RetrySettlement | RefundExcess | MintTokens | SetPause | CloseMinting | SetMetadata | FreezeMetadata | ProposeOwner | AcceptOwner | RenounceOwner | SetRole | FreezeWallet | TopUpTons
type MasterBounce = InternalTransferStep | ServicePayment
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy MasterBounce.fromSlice(in.bouncedBody);
    var s = lazy MasterStorage.load();val config = s.config.load();val e = config.economics.load();
    match (msg) {
        InternalTransferStep => {
            if(s.phase==1){
                assert(in.senderAddress==walletAddress(config.creator,contract.getAddress(),s.controls.load().walletCode) && msg.queryId==queryIdFor(config) && msg.jettonAmount==e.initialSupply) throw 710;
                s.phase=3;s.save();refundAllToCreator(config);
            }else{
                var ctl=s.controls.load();val p=ctl.pendingMints.mustGet(msg.queryId,710);
                assert(in.senderAddress==p.wallet && msg.jettonAmount==p.amount) throw 710;
                s.totalSupply-=p.amount;if(ctl.lifetimeCap){ctl.issued-=p.amount;}ctl.pendingMints.delete(msg.queryId);s.controls=ctl.toCell();s.save();
            }
        }
        ServicePayment => {
            // A bounce only contains the first 256 bits. queryId fits there.
            assert (s.phase == 2 && in.senderAddress == config.treasury && msg.queryId == queryIdFor(config) && e.serviceFee > 0) throw 710;
            s.phase = 4;s.save();
        }
        else => throw 703
    }
}
fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) { return; }
    val msg = lazy MasterMessage.fromSlice(in.body);
    var s = lazy MasterStorage.load();val config = s.config.load();val e = config.economics.load();
    match (msg) {
        LaunchCreation => {
            requireQuery(config, msg.queryId);
            assert (s.phase == 0 && in.senderAddress == config.identity.load().launcher) throw 711;
            if (blockchain.now() > config.deadline) {s.phase = 3;s.save();refundAllToCreator(config);return;}
            assert (in.valueCoins >= e.minimumLaunchValue && e.initialSupply > 0 && e.mintValue >= requiredMintValue()) throw 705;
            assert(e.initialSupply<=s.controls.load().maximum && s.controls.load().issued==0) throw 724;
            var r = s.receipts.load();r.launchLt = in.createdLt;s.receipts = r.toCell();
            s.phase = 1;s.save();
            reserveGramsOnBalance(e.serviceFee + e.recipientTopup + e.storageReserve, RESERVE_MODE_EXACT_AMOUNT);
            val payload = beginCell().storeUint(0,1).endCell().beginParse();
            val mint = createMessage({bounce: BounceMode.Only256BitsOfBody, dest: deployedWallet(config.creator, contract.getAddress(), s.controls.load().walletCode), value: e.mintValue, body: InternalTransferStep {queryId: msg.queryId, jettonAmount: e.initialSupply, transferInitiator: null, sendExcessesTo: contract.getAddress(), forwardTonAmount: 0, forwardPayload: payload}});
            mint.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        ReturnExcessesBack => {
            if(msg.queryId!=queryIdFor(config)){
                var ctl=s.controls.load();val p=ctl.pendingMints.mustGet(msg.queryId,710);assert(in.senderAddress==p.wallet) throw 710;
                ctl.pendingMints.delete(msg.queryId);s.controls=ctl.toCell();s.save();
                val refund=createMessage({bounce:BounceMode.NoBounce,dest:p.requester,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});
                refund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);return;
            }
            requireQuery(config, msg.queryId);
            assert (in.senderAddress == walletAddress(config.creator, contract.getAddress(), s.controls.load().walletCode)) throw 710;
            if (s.phase == 2 || s.phase == 4) {refundExcessToCreator(config,in.valueCoins);return;}
            assert (s.phase == 1) throw 712;
            s.receipts = settlementReceipt(s.receipts, in.senderAddress, in.createdLt, e.serviceFee);
            s.totalSupply = e.initialSupply;var ctl=s.controls.load();ctl.issued=e.initialSupply;s.controls=ctl.toCell();s.phase = 2;s.save();
            payServiceAndRefund(config);
        }
        BurnNotificationForMinter => {
            assert (s.controls.load().burnable && (s.phase == 2 || s.phase == 4) && in.senderAddress == walletAddress(msg.burnInitiator, contract.getAddress(), s.controls.load().walletCode) && msg.jettonAmount > 0 && s.totalSupply >= msg.jettonAmount) throw 713;
            s.totalSupply -= msg.jettonAmount;s.save();
            if (msg.sendExcessesTo != null) {
                val excess = createMessage({bounce: BounceMode.NoBounce, dest: msg.sendExcessesTo, value: 0, body: ReturnExcessesBack {queryId: msg.queryId}});
                excess.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
            }
        }
        RequestWalletAddress => {
            val owner = msg.includeOwnerAddress ? msg.ownerAddress.toCell() : null;
            val addr = msg.ownerAddress.getWorkchain() == 0 ? walletAddress(msg.ownerAddress, contract.getAddress(), s.controls.load().walletCode) : null;
            val response = createMessage({bounce: BounceMode.NoBounce,dest: in.senderAddress,value:0,body:ResponseWalletAddress {queryId: msg.queryId,jettonWalletAddress: addr,ownerAddress: owner}});
            response.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        RetrySettlement => {
            requireQuery(config,msg.queryId);
            assert (in.valueCoins >= mintReceiptValue() + calculateGasFee(0,25000)) throw 705;
            if (s.phase == 1) {
                val retry = createMessage({bounce: BounceMode.Only256BitsOfBody,dest:walletAddress(config.creator,contract.getAddress(),s.controls.load().walletCode),value:0,body:RetryMintReceipt {queryId:msg.queryId}});
                retry.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            } else {
                assert (s.phase == 4) throw 712;
                s.receipts = settlementReceipt(s.receipts, in.senderAddress, in.createdLt, e.serviceFee);
                s.phase=2;s.save();payServiceAndRefund(config);
            }
        }
        RefundExcess => {
            requireQuery(config,msg.queryId);
            assert (s.phase==2) throw 712;
            refundExcessToCreator(config,in.valueCoins);
        }
        MintTokens => {
            var ctl=s.controls.load();requireRole(ctl,in.senderAddress,1);
            assert(s.phase==2 && ctl.mintable && !ctl.paused && msg.recipient.getWorkchain()==0 && msg.amount>0 && s.totalSupply+msg.amount<=ctl.maximum && (!ctl.lifetimeCap || ctl.issued+msg.amount<=ctl.maximum)) throw 724;
            assert(msg.queryId!=queryIdFor(config) && in.valueCoins>=requiredMintValue()+calculateGasFee(0,35000)+calculateForwardFee(0,30000,128)) throw 705;
            assert(!ctl.pendingMints.exists(msg.queryId)) throw 723;s.totalSupply+=msg.amount;ctl.issued=min(1329227995784915872903807060280344575,ctl.issued+msg.amount) as coins;ctl.pendingMints.set(msg.queryId,PendingMint{wallet:walletAddress(msg.recipient,contract.getAddress(),ctl.walletCode),amount:msg.amount,requester:in.senderAddress});s.controls=ctl.toCell();s.save();
            val mint=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:deployedWallet(msg.recipient,contract.getAddress(),s.controls.load().walletCode),value:0,body:InternalTransferStep{queryId:msg.queryId,jettonAmount:msg.amount,transferInitiator:null,sendExcessesTo:contract.getAddress(),forwardTonAmount:0,forwardPayload:beginCell().storeUint(0,1).endCell().beginParse()}});
            mint.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        SetPause => {var ctl=s.controls.load();requireRole(ctl,in.senderAddress,2);assert(ctl.pausable) throw 724;ctl.paused=msg.paused;s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        CloseMinting => {var ctl=s.controls.load();requireOwner(ctl,in.senderAddress);ctl.mintable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        SetMetadata => {var ctl=s.controls.load();requireRole(ctl,in.senderAddress,4);assert(ctl.metadataMutable) throw 724;s.content=msg.content;s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        FreezeMetadata => {var ctl=s.controls.load();requireOwner(ctl,in.senderAddress);ctl.metadataMutable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        ProposeOwner => {var ctl=s.controls.load();requireOwner(ctl,in.senderAddress);assert(msg.owner.getWorkchain()==0) throw 701;ctl.pendingOwner=msg.owner;s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        AcceptOwner => {var ctl=s.controls.load();assert(ctl.pendingOwner!=null && in.senderAddress==ctl.pendingOwner!) throw 710;ctl.owner=in.senderAddress;ctl.pendingOwner=null;ctl.roles=createEmptyMap();s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        RenounceOwner => {var ctl=s.controls.load();requireOwner(ctl,in.senderAddress);assert(!ctl.paused && !ctl.freezable) throw 724;ctl.owner=null;ctl.pendingOwner=null;ctl.roles=createEmptyMap();ctl.mintable=false;ctl.metadataMutable=false;ctl.freezable=false;s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        SetRole => {var ctl=s.controls.load();requireOwner(ctl,in.senderAddress);assert(msg.roles<=15 && msg.account.getWorkchain()==0) throw 724;if(msg.roles==0){ctl.roles.delete(msg.account);}else{ctl.roles.set(msg.account,msg.roles);}s.controls=ctl.toCell();s.save();refundCommandBudget(config,in.senderAddress,in.valueCoins);}
        FreezeWallet => {
            val ctl=s.controls.load();requireRole(ctl,in.senderAddress,8);assert(ctl.freezable && msg.account.getWorkchain()==0 && in.valueCoins>=grams("0.1")) throw 724;
            val freeze=createMessage({bounce:BounceMode.Only256BitsOfBody,dest:deployedWallet(msg.account,contract.getAddress(),s.controls.load().walletCode),value:0,body:SetWalletFrozen{queryId:msg.queryId,frozen:msg.frozen,response:in.senderAddress}});
            freeze.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        TopUpTons => {}
        else => throw 703
    }
}
get fun get_jetton_data(): (int, bool, address?, cell, cell) {
    val s=lazy MasterStorage.load();val ctl=s.controls.load();return (s.totalSupply,ctl.mintable,ctl.owner,s.content,s.controls.load().walletCode);
}
get fun get_wallet_address(owner: address): address {
    val s=lazy MasterStorage.load();return walletAddress(owner,contract.getAddress(),s.controls.load().walletCode);
}
get fun get_creation_state(): (int,int,int) {
    val s=lazy MasterStorage.load();val c=s.config.load();val e=c.economics.load();return(s.phase,c.quoteId,e.initialSupply);
}

fun requireOwner(c:TokenControls,sender:address){assert(c.owner!=null && sender==c.owner!) throw 710;}
fun requireRole(c:TokenControls,sender:address,bit:int){if(c.owner!=null && sender==c.owner!){return;}val r=c.roles.get(sender);assert(r.isFound && (r.loadValue() & bit)!=0 && c.owner!=null) throw 710;}
get fun get_token_controls():cell {return MasterStorage.load().controls;}
