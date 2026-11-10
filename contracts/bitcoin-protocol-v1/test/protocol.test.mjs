import test from 'node:test';
import assert from 'node:assert/strict';
import * as btc from '@scure/btc-signer';
import {hex,base64} from '@scure/base';
import {secp256k1,schnorr} from '@noble/curves/secp256k1';
import * as protocol from '../src/protocol.js';

const secret=n=>{const key=new Uint8Array(32);key[31]=n;return key;};
const paymentKey=secret(1),ownerKey=secret(2),serviceKey=secret(3);
const compressed=secp256k1.getPublicKey(paymentKey,true),xonly=schnorr.getPublicKey(ownerKey);
const owner={address:btc.p2tr(xonly).address,public_key:hex.encode(xonly)};
function fixture(type='wpkh'){
 const p=type==='wpkh'?btc.p2wpkh(compressed):type==='sh'?btc.p2sh(btc.p2wpkh(compressed)):btc.p2tr(compressed.slice(1));
 const payment={address:p.address,public_key:hex.encode(compressed)};
 const prev=new btc.Transaction({allowUnknownInputs:true,allowUnknownOutputs:true});prev.addOutputAddress(p.address,1000000n);prev.addInput({txid:'11'.repeat(32),index:0,finalScriptSig:Uint8Array.of(81)});
 const input={txid:prev.id,index:0,amount:'1000000',script:hex.encode(p.script),previous_tx:hex.encode(prev.toBytes(true,false)),account:payment,confirmed:true,coinbase:false,confirmations:101,asset_checked:true,runes:[],inscriptions:[]};
 return {id:'12'.repeat(32),operation:'fixed',inputs:[input],owner,payment,service_public_key:hex.encode(schnorr.getPublicKey(serviceKey)),recipient:owner.address,treasury:p.address,service_fee:'10000',fee_rate:2,height:975300,rune:{name:'ROCKTHECOINPROTOCOL',premine:'1000000'}};
}
function walletSign(stage,key){const tx=btc.Transaction.fromPSBT(base64.decode(stage.psbt),{allowUnknownInputs:true,allowUnknownOutputs:true});for(let i=0;i<stage.inputs.length;i++)tx.signIdx(key,i,[1]);return base64.encode(tx.toPSBT());}
for(const type of ['wpkh','sh','tr'])test('creation, reveal and unilateral refund signatures verify for '+type+' funding',()=>{
 const p=protocol.cosign(protocol.creationPlan(fixture(type)),serviceKey);
 const c=protocol.verifySigned(p.commit,walletSign(p.commit,paymentKey));assert.equal(c.txid,p.commit.txid);assert.equal(protocol.verifyRaw(p.commit,c.raw).txid,c.txid);
 const r=protocol.verifySigned(p.reveal,walletSign(p.reveal,ownerKey));assert.equal(r.txid,p.reveal.txid);assert.equal(protocol.verifyRaw(p.reveal,r.raw).txid,r.txid);
 const f=protocol.verifySigned(p.refund,walletSign(p.refund,ownerKey));assert.equal(f.txid,p.refund.txid);assert.equal(protocol.verifyRaw(p.refund,f.raw).txid,f.txid);
 assert.equal(p.service_fee,'10000');assert.equal(p.required_commit_confirmations,6);assert.notEqual(r.txid,f.txid);
});
test('changing a creation output or removing the service authorization cannot pass signature verification',()=>{
 const p=protocol.cosign(protocol.creationPlan(fixture()),serviceKey),tx=btc.Transaction.fromPSBT(base64.decode(p.reveal.psbt),{allowUnknownInputs:true,allowUnknownOutputs:true});
 tx.updateOutput(1,{amount:1n},true);assert.throws(()=>protocol.verifySigned(p.reveal,base64.encode(tx.toPSBT())),/differs/);
 const noService=protocol.creationPlan(fixture());assert.throws(()=>protocol.verifySigned(noService.reveal,walletSign(noService.reveal,ownerKey)),/service authorization/);
});
test('each order commits its unique reference and funds only its exact signed reveal',()=>{
 const a=protocol.creationPlan(fixture()),b=protocol.creationPlan({...fixture(),id:'13'.repeat(32)});assert.notEqual(a.commit_address,b.commit_address);assert.notEqual(a.commit.txid,b.commit.txid);
 assert.throws(()=>protocol.cosign(a,secret(4)),/does not match/);
});
test('original funding bytes and clean asset state are mandatory',()=>{
 const f=fixture();for(const patch of [{asset_checked:false},{runes:[{name:'OTHER',amount:'1'}]},{inscriptions:['id']},{amount:'999999'},{txid:'00'.repeat(32)},{previous_tx:'00'}])assert.throws(()=>protocol.creationPlan({...f,inputs:[{...f.inputs[0],...patch}]}));
});
test('NFT and collection metadata use a distinct refund leaf without an inscription envelope',()=>{
 for(const operation of ['nft','collection']){
  const p=protocol.cosign(protocol.creationPlan({...fixture(),operation,name:'Rock',content_type:'text/plain;charset=utf-8',content_base64:base64.encode(new TextEncoder().encode('hello'))}),serviceKey);
  assert.equal(p.required_commit_confirmations,1);assert(p.content_hash);assert.equal(p.rune,null);
  const refund=btc.Script.decode(hex.decode(p.refund.inputs[0].leaf_script));assert.equal(refund.length,2);assert.equal(refund[1],'CHECKSIG');
  assert(protocol.verifySigned(p.reveal,walletSign(p.reveal,ownerKey)).raw);
 }
});
test('Rune transfers keep every unselected Rune in a dedicated return output',()=>{
 const f=fixture(),asset={...f.inputs[0],runes:[{name:'ROCK',amount:'1000'},{name:'OTHER',amount:'777'}]},p=protocol.toolPlan({...f,operation:'rune-transfer',inputs:[],asset_inputs:[asset],rune:{id:'840000:1',name:'ROCK'},recipients:[{address:owner.address,amount:'50'}]});
 assert.equal(p.expected_assets.input_balance,'1000');assert.notEqual(p.expected_assets.change_output,p.transaction.change_index);assert.equal(p.transaction.inputs[0].amount,'1000000');assert(protocol.verifySigned(p.transaction,walletSign(p.transaction,paymentKey)).raw);
});
test('BTC multisender cannot consume a Rune-bearing output',()=>{
 const f=fixture();assert.throws(()=>protocol.toolPlan({...f,operation:'btc-multisender',inputs:[{...f.inputs[0],runes:[{name:'ROCK',amount:'1'}]}],recipients:[{address:owner.address,amount:'10000'}]}));
});
test('inscription transfer returns the prefix sats and preserves the exact inscription location',()=>{
 const f=fixture(),asset={...f.inputs[0],inscriptions:['22'.repeat(32)+'i0']},p=protocol.toolPlan({...f,operation:'inscription-transfer',inputs:[],asset_inputs:[asset],inscription:{id:asset.inscriptions[0],sat_offset:'10000'},recipient:owner.address});
 assert.equal(p.expected_assets.output,1);assert.equal(p.expected_assets.sat_offset,'0');assert(protocol.verifySigned(p.transaction,walletSign(p.transaction,paymentKey)).raw);
});
test('Rune artwork and initial Rune units use separate outputs',()=>{
 const p=protocol.cosign(protocol.creationPlan({...fixture(),content_type:'text/plain;charset=utf-8',content_base64:base64.encode(new TextEncoder().encode('associated art'))}),serviceKey);
 assert.equal(p.asset_postage,'1092');assert.equal(p.inscription_output_index,0);assert.equal(p.recipient_output_index,1);assert(protocol.verifySigned(p.reveal,walletSign(p.reveal,ownerKey)).raw);
});
test('parent provenance spends and returns the complete parent before the new child output',()=>{
 const f=fixture(),parentTx=new btc.Transaction({allowUnknownInputs:true,allowUnknownOutputs:true});parentTx.addOutputAddress(owner.address,10000n);parentTx.addInput({txid:'33'.repeat(32),index:0,finalScriptSig:Uint8Array.of(81)});
 const parentId='44'.repeat(32)+'i256',parent={...f.inputs[0],txid:parentTx.id,amount:'10000',script:hex.encode(btc.p2tr(xonly).script),account:owner,previous_tx:hex.encode(parentTx.toBytes(true,false)),inscriptions:[parentId]};
 const p=protocol.cosign(protocol.creationPlan({...f,operation:'collection-mint',parent,parent_id:parentId,content_type:'text/plain;charset=utf-8',content_base64:base64.encode(new TextEncoder().encode('child'))}),serviceKey);
 assert.equal(p.creation_input_index,1);assert.equal(p.recipient_output_index,1);assert.equal(p.parent_outpoint,parentTx.id+':0');assert.equal(p.reveal.inputs[0].amount,'10000');
 const signed=protocol.verifySigned(p.reveal,walletSign(p.reveal,ownerKey)),tx=btc.Transaction.fromRaw(hex.decode(signed.raw),{allowUnknownOutputs:true,allowUnknownInputs:true});assert.equal(tx.getOutput(0).amount,10000n);assert.equal(hex.encode(tx.getOutput(0).script),parent.script);
});
test('public mint terms are permanent, exact and within uint128',()=>{
 const f=fixture(),p=protocol.creationPlan({...f,operation:'open-mint',rune:{name:f.rune.name,divisibility:38,premine:'1',amount:'123',cap:'9999',offset_start:'6',offset_end:'1000'}});assert.equal(p.rune.terms.cap,'9999');assert.equal(p.rune.divisibility,38);
 for(const rune of [{premine:'0'},{open_mint:true,amount:'1',cap:'0'},{open_mint:true,amount:'340282366920938463463374607431768211455',cap:'2'},{divisibility:39},{open_mint:true,amount:'1',cap:'2',height_start:'100',height_end:'100'}])assert.throws(()=>protocol.normalizeRune({name:f.rune.name,...rune}));
 assert.throws(()=>protocol.creationPlan({...f,rune:{name:'A',premine:'1'},height:840000}),/not unlocked/);
});
test('reveal fee adjustment and unilateral refund preserve the original commit and fee recipient',()=>{
 const p=protocol.cosign(protocol.creationPlan(fixture()),serviceKey),refund=protocol.recoveryPlan({plan:p,stage:'refund',fee_rate:5});assert.equal(refund.commit.txid,p.commit.txid);assert(BigInt(refund.refund.network_fee)>BigInt(p.refund.network_fee));assert(protocol.verifySigned(refund.refund,walletSign(refund.refund,ownerKey)).raw);
 const f=fixture(),old=btc.Transaction.fromRaw(hex.decode(f.inputs[0].previous_tx),{allowUnknownInputs:true,allowUnknownOutputs:true}),extra=structuredClone(f.inputs[0]);old.updateOutput(0,{amount:200000n},true);extra.previous_tx=hex.encode(old.toBytes(true,false));extra.txid=old.id;extra.amount='200000';
 const changed=protocol.cosign(protocol.recoveryPlan({plan:p,stage:'reveal',fee_rate:8,inputs:[extra]}),serviceKey);assert.equal(changed.commit.txid,p.commit.txid);assert.equal(changed.service_fee,p.service_fee);const tx=btc.Transaction.fromPSBT(base64.decode(changed.reveal.psbt),{allowUnknownInputs:true,allowUnknownOutputs:true});tx.signIdx(ownerKey,0,[1]);tx.signIdx(paymentKey,1,[1]);assert(protocol.verifySigned(changed.reveal,base64.encode(tx.toPSBT())).raw);
});
test('all Rune change is explicit and aggregate balances cannot overflow',()=>{
 const f=fixture(),asset={...f.inputs[0],runes:[{name:'ROCK',amount:'1000'},{name:'OTHER',amount:'777'}]},p=protocol.toolPlan({...f,operation:'burn',inputs:[],asset_inputs:[asset],rune:{id:'840000:1',name:'ROCK'},amount:'50'});assert.deepEqual(p.expected_assets.change_runes,[{name:'ROCK',amount:'950'},{name:'OTHER',amount:'777'}]);assert(p.expected_assets.burn);
 assert.throws(()=>protocol.toolPlan({...f,operation:'rune-mint',rune:{id:'840000:1',name:'ROCK',mintable:false,mint_amount:'100'}}),/not currently/);
});
test('relay policy bounds oversized Rune recipient data',()=>{
 const f=fixture(),asset={...f.inputs[0],runes:[{name:'ROCK',amount:'1000'}]};assert.throws(()=>protocol.toolPlan({...f,operation:'rune-multisender',inputs:[],asset_inputs:[asset],rune:{id:'840000:1',name:'ROCK'},recipients:Array.from({length:50},()=>({address:owner.address,amount:'1'}))}),/relay size/);
});
