tolk 1.5
import "@stdlib/gas-payments"
import "messages"

// The factory is immutable. It authorizes StateInit cells; each child retains
// the exact quoted payment until its own creation/funding acknowledgement.
struct PendingLaunch { creator: address; asset: address }
struct PendingOwner { owner: address? }
struct FactoryStorage {
    owner: address
    pendingOwner: Cell<PendingOwner>
    treasury: address
    signer: uint256
    paused: bool
    pending: map<uint64, PendingLaunch>
}
type FactoryMessage = FactoryLaunch | FactoryReceipt | ConfigureService | ProposeOwner | AcceptOwner | TopUpTons
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy LaunchCreation.fromSlice(in.bouncedBody);
    var s = FactoryStorage.fromCell(contract.getData());
    val p = s.pending.mustGet(msg.queryId, 721);
    assert (in.senderAddress == p.asset) throw 710;
    s.pending.delete(msg.queryId);contract.setData(s.toCell());
    val refund = createMessage({bounce:BounceMode.NoBounce,dest:p.creator,value:0,body:ReturnExcessesBack{queryId:msg.queryId}});
    refund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
}
fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) { return; }
    val msg = lazy FactoryMessage.fromSlice(in.body);
    var s = FactoryStorage.fromCell(contract.getData());
    match (msg) {
        FactoryLaunch => {
            val network=blockchain.configParam(19);
            assert(network!=null && network!.beginParse().loadInt(32)==-239) throw 725;
            val t = msg.terms.load();val e = t.endpoints.load();val code = t.template.load();
            assert (!s.paused && t.domain == 0x52544332 && t.deadline >= blockchain.now() && t.deadline <= blockchain.now()+300) throw 711;
            assert (e.factory == contract.getAddress() && e.treasury == s.treasury && in.senderAddress == t.creator) throw 710;
            assert (isSignatureValid(msg.terms.hash(), msg.signature as slice, s.signer)) throw 722;
            val id = (t.quoteId >> 192) as uint64;
            assert (!s.pending.exists(id)) throw 723;
            val deploy: AutoDeployAddress = {workchain:0,stateInit:{code:code.code,data:code.data}};
            assert (in.valueCoins >= t.value + grams("0.05") + calculateGasFee(0,40000) + calculateForwardFee(0,100000,400)) throw 705;
            reserveGramsOnBalance(max(grams("0.1"),contract.getOriginalBalance()-in.valueCoins+grams("0.05")),RESERVE_MODE_EXACT_AMOUNT);
            s.pending.set(id,PendingLaunch{creator:t.creator,asset:deploy.calculateAddress()});contract.setData(s.toCell());
            val launch = createMessage({bounce:BounceMode.Only256BitsOfBody,dest:deploy,value:0,body:LaunchCreation{queryId:id}});
            launch.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        FactoryReceipt => {
            if(!s.pending.exists(msg.queryId)){return;}
            val p = s.pending.mustGet(msg.queryId,721);assert (in.senderAddress == p.asset) throw 710;
            s.pending.delete(msg.queryId);contract.setData(s.toCell());
            val refund = createMessage({bounce:BounceMode.NoBounce,dest:p.creator,value:grams("0.03"),body:ReturnExcessesBack{queryId:msg.queryId}});
            refund.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
        }
        ConfigureService => {
            assert (in.senderAddress == s.owner && msg.treasury.getWorkchain() == 0 && msg.signer != 0) throw 710;
            s.treasury=msg.treasury;s.signer=msg.signer;s.paused=msg.paused;contract.setData(s.toCell());
        }
        ProposeOwner => {assert(in.senderAddress==s.owner && msg.owner.getWorkchain()==0) throw 710;s.pendingOwner=PendingOwner{owner:msg.owner}.toCell();contract.setData(s.toCell());}
        AcceptOwner => {assert(s.pendingOwner.load().owner!=null && in.senderAddress==s.pendingOwner.load().owner!) throw 710;s.owner=in.senderAddress;s.pendingOwner=PendingOwner{owner:null}.toCell();contract.setData(s.toCell());}
        TopUpTons => {}
        else => throw 703
    }
}
get fun get_service_data(): (address,address?,address,int,bool,int) {
    val s=FactoryStorage.fromCell(contract.getData());return(s.owner,s.pendingOwner.load().owner,s.treasury,s.signer,s.paused,2);
}
