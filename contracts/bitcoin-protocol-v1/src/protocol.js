// RockTheCoin Bitcoin transaction protocol V1. No network access, broadcasting,
// wallet keys or application configuration. Integer asset amounts stay strings.
import * as btc from '@scure/btc-signer';
import {hex,base64} from '@scure/base';
import {sha256} from '@noble/hashes/sha256';
import {secp256k1,schnorr} from '@noble/curves/secp256k1';

export class BitcoinProtocolError extends Error {constructor(message){super(message);this.status=422;}}
const fail=message=>{throw new BitcoinProtocolError(message);};
const U128=(1n<<128n)-1n,MONEY=21000000n*100000000n,utf8=new TextEncoder();
const eq=(a,b)=>a instanceof Uint8Array&&b instanceof Uint8Array&&hex.encode(a)===hex.encode(b);
const bytes=value=>typeof value==='string'?hex.decode(value):value;
const json=value=>JSON.parse(JSON.stringify(value,(_,v)=>typeof v==='bigint'?v.toString():v));
function uint(value,label='amount',max=U128){if(typeof value!=='string'||!/^(0|[1-9][0-9]{0,38})$/.test(value))fail('Use an exact integer for '+label+'.');const n=BigInt(value);if(n>max)fail(label+' exceeds its limit.');return n;}
function index(value,label,max=0xffffffff){if(!Number.isSafeInteger(value)||value<0||value>max)fail('Invalid '+label+'.');return value;}
export function address(value){try{const a=btc.Address().decode(value);if(!['pkh','sh','wpkh','wsh','tr'].includes(a.type))fail('Unsupported Bitcoin address.');return btc.Address().encode(a);}catch{fail('Use a checksummed Bitcoin mainnet address.');}}
function outpoint(value){if(typeof value!=='string'||!/^([a-f0-9]{64}):(0|[1-9][0-9]{0,9})$/.test(value))fail('Invalid Bitcoin output.');const [txid,n]=value.split(':');return {txid,index:index(Number(n),'output index')};}
function compact(n){if(n<253)return Uint8Array.of(n);if(n<=65535)return Uint8Array.of(253,n&255,n>>>8);return Uint8Array.of(254,n&255,(n>>>8)&255,(n>>>16)&255,(n>>>24)&255);}
function tagged(tag,payload){const t=sha256(utf8.encode(tag));return sha256(Uint8Array.from([...t,...t,...payload]));}
function leafHash(script){return tagged('TapLeaf',Uint8Array.from([0xc0,...compact(script.length),...script]));}
export function leb128(n){if(typeof n!=='bigint'||n<0n||n>U128)fail('Invalid Rune integer.');const out=[];do{const b=Number(n&127n);n>>=7n;out.push(b|(n?128:0));}while(n);return Uint8Array.from(out);}
export function runeName(value){
 if(typeof value!=='string'||value.length>55||!/^[A-Z]+(?:[•.][A-Z]+)*$/.test(value))fail('Use uppercase Rune letters with optional spacers.');
 let n=0n,spacers=0n,count=0;for(const c of value){if(c==='•'||c==='.'){spacers|=1n<<BigInt(count-1);continue;}if(count++)n++;n=n*26n+BigInt(c.charCodeAt(0)-65);if(n>U128)fail('Rune name exceeds uint128.');}
 const commitment=[];for(let v=n;v;v>>=8n)commitment.push(Number(v&255n));
 return {name:value.replace(/[•.]/g,''),spaced_name:value.replace(/\./g,'•'),number:n,spacers,commitment:Uint8Array.from(commitment),reserved:n>=6402364363415443603228541259936211926n};
}
export function runeUnlockHeight(value){
 const r=runeName(value);if(r.reserved)fail('Choose a non-reserved Rune name.');
 const steps=[0n];for(let i=1;i<=13;i++)steps.push((steps[i-1]+1n)*26n);
 if(r.number>=steps[12])return 0;
 const i=steps.findIndex(v=>r.number<v),interval=steps[i]-steps[i-1],progress=steps[i]-r.number;
 return 840000+(12-i)*17500+Number((progress*17500n-1n)/interval);
}
export function normalizeRune(input){
 const r=runeName(input?.name);if(r.reserved)fail('Choose a non-reserved Rune name.');
 const divisibility=index(input.divisibility??0,'Rune divisibility',38),symbol=input.symbol??'';
 if(typeof symbol!=='string'||[...symbol].length>1||/[\p{C}]/u.test(symbol))fail('Use one visible Rune symbol.');
 const premine=uint(input.premine??'0','initial allocation');let terms=null;
 if(input.open_mint===true){const amount=uint(input.amount,'mint amount'),cap=uint(input.cap,'mint cap');if(amount===0n||cap===0n||premine+amount*cap>U128)fail('Mint amount and cap must fit the Rune supply.');terms={amount,cap};for(const k of ['height_start','height_end','offset_start','offset_end'])if(input[k]!==undefined&&input[k]!=='')terms[k]=uint(input[k],k,(1n<<64n)-1n);for(const [a,b] of [['height_start','height_end'],['offset_start','offset_end']])if(terms[a]!==undefined&&terms[b]!==undefined&&terms[b]<=terms[a])fail('Mint end must follow mint start.');}
 else if(input.open_mint!==undefined&&input.open_mint!==false)fail('Invalid public mint option.');
 if(!terms&&premine===0n)fail('Fixed issuance needs a positive initial allocation.');return {...r,divisibility,symbol,premine,terms};
}
function runestone(fields,edicts=[]){
 const values=[...fields];if(edicts.length){values.push(0n);let lastBlock=0n,lastTx=0n;for(const e of edicts){const [block,tx]=e.id.split(':').map(BigInt);if(block<lastBlock||(block===lastBlock&&tx<lastTx))fail('Rune edicts must be ordered.');values.push(block-lastBlock,block===lastBlock?tx-lastTx:tx,e.amount,BigInt(e.output));lastBlock=block;lastTx=tx;}}
 const payload=Uint8Array.from(values.flatMap(n=>[...leb128(n)])),parts=[];for(let i=0;i<payload.length;i+=520)parts.push(payload.slice(i,i+520));const script=btc.Script.encode(['RETURN',13,...parts]);if(script.length>83)fail('Rune data exceeds the supported relay size. Use fewer recipients or shorter mint settings.');return script;
}
function etching(r,pointer){const f=[2n,r.terms?3n:1n,4n,r.number,1n,BigInt(r.divisibility),22n,BigInt(pointer)];if(r.spacers)f.push(3n,r.spacers);if(r.symbol)f.push(5n,BigInt(r.symbol.codePointAt(0)));if(r.premine)f.push(6n,r.premine);if(r.terms){f.push(8n,r.terms.cap,10n,r.terms.amount);for(const [k,t] of [['height_start',12n],['height_end',14n],['offset_start',16n],['offset_end',18n]])if(r.terms[k]!==undefined)f.push(t,r.terms[k]);}return runestone(f);}
function cborText(s){const b=utf8.encode(s),n=b.length;return Uint8Array.from([...(n<24?[0x60+n]:n<256?[0x78,n]:[0x79,n>>>8,n&255]),...b]);}
function metadata(value){const entries=Object.entries(value).filter(([,v])=>typeof v==='string'&&v!=='');if(entries.length>10)fail('Too many metadata fields.');return Uint8Array.from([0xa0+entries.length,...entries.flatMap(([k,v])=>[...cborText(k),...cborText(v)])]);}
function inscriptionEnvelope(content,type,info,parent){
 if(!(content instanceof Uint8Array)||content.length<1||content.length>131072)fail('Use inscription content between 1 byte and 128 KiB.');
 if(!['image/png','image/jpeg','image/webp','image/gif','text/plain;charset=utf-8','application/json'].includes(type))fail('Unsupported inscription content type.');
 const script=[0,'IF',utf8.encode('ord'),Uint8Array.of(1),utf8.encode(type)];
 if(info?.name||info?.description)script.push(Uint8Array.of(5),metadata(info));
 if(parent){if(!/^[a-f0-9]{64}i(0|[1-9][0-9]{0,9})$/.test(parent))fail('Invalid collection parent.');const [tx,n]=parent.split('i');index(Number(n),'parent inscription index');const suffix=[];for(let v=BigInt(n);v;v>>=8n)suffix.push(Number(v&255n));script.push(Uint8Array.of(3),Uint8Array.from([...hex.decode(tx).reverse(),...suffix]));}
 script.push(0);for(let i=0;i<content.length;i+=520)script.push(content.slice(i,i+520));script.push('ENDIF');return script;
}
export function account(input){
 const a=address(input?.address),key=bytes(input?.public_key??input?.publicKey??'');let payment;
 try{if(key.length===32)payment=btc.p2tr(key);else if(key.length===33){const decoded=btc.Address().decode(a);payment=decoded.type==='wpkh'?btc.p2wpkh(key):decoded.type==='sh'?btc.p2sh(btc.p2wpkh(key)):decoded.type==='tr'?btc.p2tr(key.slice(1)):null;}if(!payment||payment.address!==a)fail('Wallet public key does not match its address.');}catch{fail('Use a matching SegWit or Taproot wallet public key.');}
 return {address:a,public_key:hex.encode(key),xonly_key:hex.encode(key.length===32?key:key.slice(1)),script:hex.encode(payment.script),type:btc.OutScript.decode(payment.script).type,...(payment.redeemScript?{redeem_script:hex.encode(payment.redeemScript)}:{}),...(payment.tapInternalKey?{tap_internal_key:hex.encode(payment.tapInternalKey)}:{})};
}
function fundingInput(u,{allowAssets=false}={}){
 const p=outpoint(u.txid+':'+u.index);if(/^0{64}$/.test(p.txid))fail('Synthetic sample inputs cannot fund a customer checkout.');
 if(u.confirmed!==true||u.asset_checked!==true||!Array.isArray(u.runes)||!Array.isArray(u.inscriptions))fail('Use confirmed, server-verified Bitcoin inputs.');
 if(!allowAssets&&(u.runes.length||u.inscriptions.length))fail('Ordinary funding cannot contain Runes or inscriptions.');
 const owner=account(u.account),amount=uint(u.amount,'input value',MONEY);if(amount===0n||u.script!==owner.script)fail('Funding script does not match the selected wallet.');
 if(u.coinbase===true&&(!Number.isInteger(u.confirmations)||u.confirmations<100))fail('Coinbase funding must mature for 100 blocks.');
 if(typeof u.previous_tx!=='string'||u.previous_tx.length>4000000)fail('The original funding transaction is required.');
 let prev;try{prev=btc.Transaction.fromRaw(hex.decode(u.previous_tx),{allowUnknownInputs:true,allowUnknownOutputs:true});}catch{fail('Invalid original funding transaction.');}
 const output=prev.getOutput(p.index);if(prev.id!==p.txid||!output||output.amount!==amount||!eq(output.script,hex.decode(u.script)))fail('Funding output differs from its original Bitcoin transaction.');
 return {txid:p.txid,index:p.index,amount,owner,source:u};
}
function newTx(){return new btc.Transaction({allowUnknownInputs:true,allowUnknownOutputs:true,version:2,lockTime:0});}
function addInput(tx,u){tx.addInput({txid:u.txid,index:u.index,sequence:0xfffffffd,sighashType:1,witnessUtxo:{amount:u.amount,script:hex.decode(u.owner.script)},...(u.owner.redeem_script?{redeemScript:hex.decode(u.owner.redeem_script),nonWitnessUtxo:hex.decode(u.source.previous_tx)}:{}),...(u.owner.tap_internal_key?{tapInternalKey:hex.decode(u.owner.tap_internal_key)}:{})});}
function descriptor(u){return {kind:'wallet',address:u.owner.address,public_key:u.owner.public_key,type:u.owner.type,amount:u.amount.toString(),script:u.owner.script,...(u.owner.redeem_script?{redeem_script:u.owner.redeem_script}:{})};}
function stableId(tx,descriptors){const clone=tx.clone();descriptors.forEach((d,i)=>{if(d.redeem_script)clone.updateInput(i,{finalScriptSig:btc.Script.encode([hex.decode(d.redeem_script)])},true);});return clone.id;}
function estimate(tx,descriptors){const c=tx.clone();descriptors.forEach((d,i)=>{let witness;if(d.kind==='creation')witness=[new Uint8Array(65),new Uint8Array(65),hex.decode(d.leaf_script),hex.decode(d.control_block)];else if(d.kind==='refund')witness=[new Uint8Array(65),hex.decode(d.leaf_script),hex.decode(d.control_block)];else if(d.type==='tr')witness=[new Uint8Array(65)];else witness=[new Uint8Array(73),hex.decode(d.public_key)];c.updateInput(i,{finalScriptWitness:witness,...(d.redeem_script?{finalScriptSig:btc.Script.encode([hex.decode(d.redeem_script)])}:{})},true);});return c.vsize;}
function rate(value){const s=String(value);if(!/^[0-9]{1,4}(?:\.[0-9]{1,3})?$/.test(s))fail('Use a fee rate with at most three decimals.');const [a,b='']=s.split('.'),n=BigInt(a)*1000n+BigInt(b.padEnd(3,'0'));if(n<1000n||n>1000000n)fail('Use a fee rate between 1 and 1,000 sat/vB.');return n;}
const minerFee=(size,r)=>(BigInt(size)*r+999n)/1000n;
function finish(tx,descriptors,total,change,r){
 let spent=0n;for(let i=0;i<tx.outputsLength;i++)spent+=tx.getOutput(i).amount;
 const changeIndex=tx.addOutputAddress(address(change),546n);let network=minerFee(estimate(tx,descriptors),r),remaining=total-spent-network;
 if(remaining<546n)fail('Insufficient verified BTC for the outputs, service fee, network fee and change.');
 tx.updateOutput(changeIndex,{amount:remaining});if(estimate(tx,descriptors)>100000)fail('This Bitcoin transaction exceeds the standard weight limit.');
 return exportPlan(tx,descriptors,network,changeIndex);
}
function exportPlan(tx,descriptors,network,changeIndex=null){const outputs=[];for(let i=0;i<tx.outputsLength;i++){const output=tx.getOutput(i);let address=null;try{address=btc.Address().encode(btc.OutScript.decode(output.script));}catch{}outputs.push({index:i,address,amount:output.amount.toString(),script:hex.encode(output.script)});}return {psbt:base64.encode(tx.toPSBT()),unsigned_tx:hex.encode(tx.unsignedTx),txid:stableId(tx,descriptors),inputs:descriptors,outputs,network_fee:network.toString(),vsize_estimate:estimate(tx,descriptors),change_index:changeIndex};}
function unique(inputs){const set=new Set();let total=0n;for(const u of inputs){const k=u.txid+':'+u.index;if(set.has(k))fail('Duplicate Bitcoin input.');set.add(k);total+=u.amount;}if(total>MONEY)fail('Input total exceeds Bitcoin supply.');return total;}
function sourceInputs(rows,options){if(!Array.isArray(rows)||rows.length<1||rows.length>20)fail('Use 1 to 20 verified Bitcoin inputs.');const out=rows.map(u=>fundingInput(u,options));unique(out);return out;}
function service(value){const fee=uint(value??'0','service fee',MONEY);if(fee>0n&&fee<546n)fail('The service fee must meet the Bitcoin dust limit.');return fee;}
function leafDescriptor(kind,payment,script,owner,serviceKey){const found=payment.tapLeafScript.find(([,s])=>eq(s.slice(0,-1),script));if(!found)fail('Missing Bitcoin script leaf.');return {kind,address:owner.address,public_key:owner.xonly_key,type:'tr',script:hex.encode(payment.script),leaf_script:hex.encode(script),control_block:hex.encode(btc.TaprootControlBlock.encode(found[0])),service_key:serviceKey};}
export function creationPlan(input){
 if(!['fixed','meme','open-mint','nft','collection','collection-mint'].includes(input.operation))fail('Choose a Bitcoin creation operation.');
 if(typeof input.id!=='string'||!/^[a-f0-9]{64}$/.test(input.id)||/^0{64}$/.test(input.id))fail('A unique Bitcoin creation reference is required.');
 const funding=sourceInputs(input.inputs),total=unique(funding),owner=account(input.owner),change=account(input.payment),recipient=address(input.recipient??owner.address),fee=service(input.service_fee),r=rate(input.fee_rate),serviceKey=bytes(input.service_public_key);
 if(serviceKey.length!==32)fail('A valid service cosigner is required.');btc.p2tr(serviceKey);if(eq(serviceKey,hex.decode(owner.xonly_key)))fail('Customer and service keys must differ.');
 const isRune=['fixed','meme','open-mint'].includes(input.operation),rune=isRune?normalizeRune({...input.rune,open_mint:input.operation==='open-mint'}):null;
 if(rune&&runeUnlockHeight(rune.spaced_name)>index(input.height,'Bitcoin block height'))fail('This Rune name is not unlocked yet.');
 let content=null;if(input.content_base64){try{content=base64.decode(input.content_base64);}catch{fail('Invalid inscription content.');}}
 if(!isRune&&!content)fail('Inscription artwork or content is required.');
 if(input.name!==undefined&&(typeof input.name!=='string'||utf8.encode(input.name).length>64))fail('Use a name up to 64 bytes.');if(input.description!==undefined&&(typeof input.description!=='string'||utf8.encode(input.description).length>2000))fail('Use a description up to 2,000 bytes.');
 const creation=[hex.decode(input.id),'DROP',hex.decode(owner.xonly_key),'CHECKSIGVERIFY',serviceKey,'CHECKSIG'];
 if(rune)creation.push(0,'IF',rune.commitment,'ENDIF');
 if(content)creation.push(...inscriptionEnvelope(content,input.content_type,{name:input.name??rune?.spaced_name??'',description:input.description??''},input.operation==='collection-mint'?input.parent_id:null));
 const script=btc.Script.encode(creation),refundScript=btc.Script.encode([hex.decode(owner.xonly_key),'CHECKSIG']);
 const tree=btc.p2tr(btc.TAPROOT_UNSPENDABLE_KEY,[{script},{script:refundScript}],undefined,true),createDesc=leafDescriptor('creation',tree,script,owner,hex.encode(serviceKey)),refundDesc=leafDescriptor('refund',tree,refundScript,owner,hex.encode(serviceKey));
 let parent=null;if(input.operation==='collection-mint'){
  if(!input.parent||!input.parent_id)fail('A verified parent inscription is required.');parent=fundingInput(input.parent,{allowAssets:true});
  if(parent.source.runes.length||!parent.source.inscriptions.includes(input.parent_id)||parent.owner.address!==owner.address)fail('The collection parent must be controlled by your Ordinals wallet and contain no Runes.');
  if(funding.some(u=>u.txid===parent.txid&&u.index===parent.index))fail('The parent cannot also fund the commit.');
 }
 const commit=newTx();funding.forEach(u=>addInput(commit,u));const commitDescriptors=funding.map(descriptor);
 // Estimate the reveal with maximum-size signature placeholders, then bind the
 // exact funded output to both the creation and unilateral refund leaves.
 const reveal=newTx();if(parent)addInput(reveal,parent);
 const revealIndex=reveal.addInput({txid:'11'.repeat(32),index:0,sequence:0xfffffffd,sighashType:1,witnessUtxo:{amount:100000n,script:tree.script},tapInternalKey:tree.tapInternalKey,tapMerkleRoot:tree.tapMerkleRoot,tapLeafScript:tree.tapLeafScript.filter(([,s])=>eq(s.slice(0,-1),script))});
 const revealDescriptors=[...(parent?[descriptor(parent)]:[]),{...createDesc,amount:'100000'}];
 if(parent)reveal.addOutputAddress(owner.address,parent.amount);
 // Artwork gets its own sat output. Keeping the Rune allocation separate
 // prevents a later Rune transfer from accidentally spending its inscription.
 const inscriptionIndex=rune&&content?reveal.addOutputAddress(recipient,546n):null;
 const recipientIndex=reveal.addOutputAddress(recipient,546n);if(fee)reveal.addOutputAddress(address(input.treasury),fee);
 if(rune)reveal.addOutput({amount:0n,script:etching(rune,recipientIndex)});
 const assetPostage=inscriptionIndex===null?546n:1092n,revealFee=minerFee(estimate(reveal,revealDescriptors),r),commitValue=assetPostage+fee+revealFee;
 commit.addOutputAddress(tree.address,commitValue);const commitPlan=finish(commit,commitDescriptors,total,change.address,r);
 reveal.updateInput(revealIndex,{txid:commitPlan.txid,witnessUtxo:{amount:commitValue,script:tree.script}},true);revealDescriptors[revealIndex].amount=commitValue.toString();
 const revealPlan=exportPlan(reveal,revealDescriptors,revealFee);
 const refund=newTx();refund.addInput({txid:commitPlan.txid,index:0,sequence:0xfffffffd,sighashType:1,witnessUtxo:{amount:commitValue,script:tree.script},tapInternalKey:tree.tapInternalKey,tapMerkleRoot:tree.tapMerkleRoot,tapLeafScript:tree.tapLeafScript.filter(([,s])=>eq(s.slice(0,-1),refundScript))});
 const refundDescriptors=[{...refundDesc,amount:commitValue.toString()}];const refundFee=minerFee(estimateWithRefundOutput(refund,refundDescriptors,change.address),r);
 if(commitValue-refundFee<546n)fail('The commit needs more BTC to support recovery.');refund.addOutputAddress(change.address,commitValue-refundFee);
 const plan={version:1,id:input.id,operation:input.operation,owner, payment:change,recipient,treasury:fee?address(input.treasury):null,service_fee:fee.toString(),service_public_key:hex.encode(serviceKey),fee_rate:String(input.fee_rate),commit:commitPlan,reveal:revealPlan,refund:exportPlan(refund,refundDescriptors,refundFee),commit_value:commitValue.toString(),asset_postage:assetPostage.toString(),commit_address:tree.address,creation_input_index:revealIndex,recipient_output_index:recipientIndex,inscription_output_index:content?(inscriptionIndex??recipientIndex):null,required_commit_confirmations:rune?6:1,content_hash:content?hex.encode(sha256(content)):null,content_type:content?input.content_type:null,parent_id:input.parent_id??null,parent_outpoint:parent?parent.txid+':'+parent.index:null,rune:rune?json(rune):null};
 return json(plan);
}
function estimateWithRefundOutput(tx,d,addr){const copy=tx.clone();copy.addOutputAddress(addr,546n);return estimate(copy,d);}
function parsePSBT(value){try{if(typeof value!=='string'||value.length>2000000)fail('Invalid Bitcoin PSBT.');return btc.Transaction.fromPSBT(base64.decode(value),{allowUnknownInputs:true,allowUnknownOutputs:true});}catch{fail('The wallet returned an invalid Bitcoin PSBT.');}}
function sighash(tx,d,i,type,leaf){const scripts=d.map(x=>hex.decode(x.script)),amounts=d.map(x=>BigInt(x.amount));return tx.preimageWitnessV1(i,scripts,type,amounts,undefined,leaf?hex.decode(leaf):undefined,leaf?0xc0:undefined);}
export function cosign(plan,privateKey){
 const key=bytes(privateKey),pub=schnorr.getPublicKey(key);if(hex.encode(pub)!==plan.service_public_key)fail('Service cosigner does not match the committed script.');
 const tx=parsePSBT(plan.reveal.psbt),i=plan.creation_input_index,d=plan.reveal.inputs[i],hash=sighash(tx,plan.reveal.inputs,i,1,d.leaf_script),sig=Uint8Array.from([...schnorr.sign(hash,key),1]);
 tx.updateInput(i,{tapScriptSig:[[{pubKey:pub,leafHash:leafHash(hex.decode(d.leaf_script))},sig]]},true);
 return {...plan,reveal:{...plan.reveal,psbt:base64.encode(tx.toPSBT())}};
}
function validSchnorr(sig,hash,key){if(!(sig instanceof Uint8Array)||(sig.length!==64&&sig.length!==65))fail('Invalid Schnorr signature.');if(!schnorr.verify(sig.slice(0,64),hash,key))fail('The Bitcoin signature does not authorize this transaction.');}
function hashType(sig){if(sig.length===64)return 0;if(sig.length===65&&sig[64]===1)return 1;fail('Only SIGHASH_ALL or Taproot SIGHASH_DEFAULT is allowed.');}
export function verifySigned(stage,signed){
 const expected=parsePSBT(stage.psbt),wallet=parsePSBT(signed);if(!eq(wallet.unsignedTx,expected.unsignedTx))fail('The signed Bitcoin transaction differs from the reviewed inputs or outputs.');
 if(stage.inputs.length!==wallet.inputsLength)fail('Incorrect Bitcoin input count.');
 for(let i=0;i<stage.inputs.length;i++){
  const d=stage.inputs[i],w=wallet.getInput(i),e=expected.getInput(i);if(w.witnessUtxo&&(!eq(w.witnessUtxo.script,e.witnessUtxo.script)||w.witnessUtxo.amount!==e.witnessUtxo.amount))fail('The wallet changed a funding output.');
  let witness;
  if(d.kind==='creation'||d.kind==='refund'){
   const script=hex.decode(d.leaf_script),control=hex.decode(d.control_block),hash=leafHash(script),key=hex.decode(d.public_key);
   const find=(input,pub)=>input.tapScriptSig?.find(([k])=>eq(k.pubKey,pub)&&eq(k.leafHash,hash))?.[1];
   const final=w.finalScriptWitness;let customer=find(w,key),server=d.kind==='creation'?find(e,hex.decode(d.service_key)):null;
   if(final){const n=d.kind==='creation'?4:3;if(final.length!==n||!eq(final[n-2],script)||!eq(final[n-1],control))fail('The wallet changed the reviewed Bitcoin script path.');customer=final[n-3];if(d.kind==='creation'){server=final[0];customer=final[1];}}
   if(!customer||customer.length!==65||hashType(customer)!==1)fail('The creation or recovery script must use SIGHASH_ALL.');validSchnorr(customer,sighash(expected,stage.inputs,i,1,d.leaf_script),key);
   if(d.kind==='creation'){if(!server||server.length!==65||hashType(server)!==1)fail('Missing service authorization.');validSchnorr(server,sighash(expected,stage.inputs,i,1,d.leaf_script),hex.decode(d.service_key));witness=[server,customer,script,control];}else witness=[customer,script,control];
  }else if(d.type==='tr'){
   const sig=w.finalScriptWitness?.length===1?w.finalScriptWitness[0]:w.tapKeySig;if(!sig)fail('The wallet did not sign a Taproot funding input.');const type=hashType(sig);validSchnorr(sig,sighash(expected,stage.inputs,i,type),hex.decode(d.script).slice(2));witness=[sig];
  }else{
   const key=hex.decode(d.public_key),partial=w.partialSig?.find(([pub])=>eq(pub,key))?.[1],sig=w.finalScriptWitness?.length===2?w.finalScriptWitness[0]:partial;
   if(!sig||sig.length<9||sig.length>73||sig[sig.length-1]!==1||(w.finalScriptWitness&&!eq(w.finalScriptWitness[1],key)))fail('The SegWit funding signature must authorize all outputs.');
   const digest=expected.preimageWitnessV0(i,btc.p2pkh(key).script,1,BigInt(d.amount));if(!secp256k1.verify(sig.slice(0,-1),digest,key,{lowS:true,prehash:false}))fail('Invalid SegWit funding signature.');witness=[sig,key];
  }
  const scriptSig=d.redeem_script?btc.Script.encode([hex.decode(d.redeem_script)]):new Uint8Array();if(w.finalScriptSig&&!eq(w.finalScriptSig,scriptSig))fail('The wallet changed a funding script signature.');expected.updateInput(i,{finalScriptWitness:witness,finalScriptSig:scriptSig},true);
 }
 const raw=expected.extract(),txid=expected.id;if(txid!==stage.txid)fail('The wallet changed the reviewed Bitcoin transaction ID.');
 let total=0n;for(const d of stage.inputs)total+=BigInt(d.amount);let sent=0n;for(let i=0;i<expected.outputsLength;i++)sent+=expected.getOutput(i).amount;
 if(total-sent!==BigInt(stage.network_fee))fail('The signed transaction changed its network fee.');return {txid,raw:hex.encode(raw),psbt:base64.encode(expected.toPSBT()),network_fee:stage.network_fee,vsize:expected.vsize};
}
export function verifyRaw(stage,raw){const parsed=btc.Transaction.fromRaw(hex.decode(raw),{allowUnknownInputs:true,allowUnknownOutputs:true}),wallet=parsePSBT(stage.psbt);if(parsed.inputsLength!==wallet.inputsLength||parsed.outputsLength!==wallet.outputsLength||parsed.version!==wallet.version||parsed.lockTime!==wallet.lockTime)fail('Committed Bitcoin transaction differs from the reviewed plan.');for(let i=0;i<parsed.inputsLength;i++){const a=parsed.getInput(i),b=wallet.getInput(i);if(!eq(a.txid,b.txid)||a.index!==b.index||a.sequence!==b.sequence)fail('Committed Bitcoin input differs.');wallet.updateInput(i,{finalScriptWitness:a.finalScriptWitness,finalScriptSig:a.finalScriptSig},true);}for(let i=0;i<parsed.outputsLength;i++){const a=parsed.getOutput(i),b=wallet.getOutput(i);if(a.amount!==b.amount||!eq(a.script,b.script))fail('Committed Bitcoin output differs.');}const result=verifySigned(stage,base64.encode(wallet.toPSBT()));if(result.raw!==raw.toLowerCase())fail('Committed Bitcoin witness differs.');return result;}

function runeId(value){if(typeof value!=='string'||!/^([1-9][0-9]{0,19}):(0|[1-9][0-9]{0,9})$/.test(value))fail('Use a Rune ID as block:transaction.');const [a,b]=value.split(':');uint(a,'Rune block',(1n<<64n)-1n);index(Number(b),'Rune transaction index');return value;}
function rows(value){if(!Array.isArray(value)||value.length<1||value.length>50)fail('Use 1 to 50 recipients.');return value.map(row=>({address:address(row.address),amount:uint(row.amount,'recipient amount')}));}
export function toolPlan(input){
 const allowed=['btc-multisender','rune-mint','rune-transfer','rune-multisender','burn','inscription-transfer','fee-refund'];if(!allowed.includes(input.operation))fail('Choose a supported Bitcoin tool.');
 const payment=account(input.payment),owner=account(input.owner),funding=input.inputs?.length?sourceInputs(input.inputs):[],assets=input.asset_inputs?.length?sourceInputs(input.asset_inputs,{allowAssets:true}):[],all=[...assets,...funding],total=unique(all),tx=newTx(),descriptors=all.map(descriptor),r=rate(input.fee_rate),fee=service(input.service_fee);
 if(!all.length)fail('Verified Bitcoin inputs are required.');all.forEach(u=>addInput(tx,u));let target=null,expectedAssets=null;
 if(input.operation==='btc-multisender'||input.operation==='fee-refund'){
  if(assets.length)fail('BTC distribution cannot spend asset-bearing inputs.');for(const row of rows(input.recipients)){if(row.amount<546n||row.amount>MONEY)fail('Each BTC recipient needs at least 546 sats.');tx.addOutputAddress(row.address,row.amount);}
 }else if(input.operation==='inscription-transfer'){
  if(assets.length!==1||assets[0].source.runes.length||assets[0].source.inscriptions.length!==1||assets[0].source.inscriptions[0]!==input.inscription?.id)fail('Transfer one inscription from an output without other inscriptions or Runes.');
  const offset=uint(input.inscription.sat_offset,'inscription sat offset',MONEY);if(offset>=assets[0].amount)fail('Inscription position is outside its output.');
  if(offset>=546n)tx.addOutputAddress(payment.address,offset);
  target=tx.addOutputAddress(address(input.recipient),546n);expectedAssets={inscription_id:input.inscription.id,output:target,sat_offset:offset>=546n?'0':offset.toString()};
 }else{
  const id=runeId(input.rune?.id),name=runeName(input.rune.name).name;
  for(const u of assets)if(u.source.inscriptions.length)fail('Rune management must not spend inscription-bearing outputs.');
  let balance=0n;for(const u of assets)for(const rune of u.source.runes)if(runeName(rune.name).name===name)balance+=uint(rune.amount,'Rune input balance');if(balance>U128)fail('Rune input balance exceeds uint128.');
  let runeRows=[];
  if(input.operation==='rune-mint'){
   if(assets.length||input.rune.mintable!==true)fail('The Rune is not currently open for minting.');
   const amount=uint(input.rune.mint_amount,'mint allocation');if(amount===0n)fail('Rune mint allocation is unavailable.');target=tx.addOutputAddress(address(input.recipient??owner.address),546n);expectedAssets={rune_name:name,amount:amount.toString(),outputs:[{output:target,amount:amount.toString()}]};
  }else{
   runeRows=input.operation==='burn'?[{address:owner.address,amount:uint(input.amount,'burn amount')}]:rows(input.recipients);
   const sent=runeRows.reduce((n,row)=>n+row.amount,0n);if(sent===0n||sent>balance||runeRows.some(row=>row.amount===0n))fail('Rune amounts must be positive and within the verified balance.');
   if(input.operation!=='burn')runeRows.forEach(row=>{row.output=tx.addOutputAddress(row.address,546n);});
   expectedAssets={rune_name:name,amount:sent.toString(),input_balance:balance.toString(),outputs:runeRows.map(row=>({output:row.output??null,amount:row.amount.toString()})),burn:input.operation==='burn'};
  }
  if(fee)tx.addOutputAddress(address(input.treasury),fee);
  const assetChange=input.operation==='rune-mint'?null:tx.addOutputAddress(owner.address,546n),opReturn=tx.outputsLength;
  if(assetChange!==null)expectedAssets.change_output=assetChange;
  if(assetChange!==null){const balances=new Map();for(const u of assets)for(const rune of u.source.runes){const n=runeName(rune.name).name,amount=(balances.get(n)??0n)+uint(rune.amount,'Rune input balance');if(amount>U128)fail('Combined Rune input balance exceeds uint128.');balances.set(n,amount);}balances.set(name,balance-BigInt(expectedAssets.amount));expectedAssets.change_runes=[...balances].filter(([,amount])=>amount>0n).map(([name,amount])=>({name,amount:amount.toString()}));}
  let script;if(input.operation==='rune-mint'){const [block,n]=id.split(':').map(BigInt);script=runestone([20n,block,20n,n,22n,BigInt(target)]);}else script=runestone([22n,BigInt(assetChange)],runeRows.map(row=>({id,amount:row.amount,output:row.output??opReturn})));
  tx.addOutput({amount:0n,script});
 }
 if(fee&&['btc-multisender','fee-refund','inscription-transfer'].includes(input.operation))tx.addOutputAddress(address(input.treasury),fee);
 const stage=finish(tx,descriptors,total,payment.address,r);
 return {version:1,operation:input.operation,payment,owner,service_fee:fee.toString(),treasury:fee?address(input.treasury):null,fee_rate:String(input.fee_rate),transaction:stage,expected_assets:expectedAssets};
}
function unsignedCopy(stage){const old=parsePSBT(stage.psbt),tx=newTx();for(let i=0;i<old.inputsLength;i++){const v=old.getInput(i),row={};for(const key of ['txid','index','sequence','sighashType','witnessUtxo','redeemScript','nonWitnessUtxo','tapInternalKey','tapMerkleRoot','tapLeafScript'])if(v[key]!==undefined)row[key]=v[key];tx.addInput(row);}for(let i=0;i<old.outputsLength;i++){const v=old.getOutput(i);tx.addOutput({amount:v.amount,script:v.script});}return tx;}
export function recoveryPlan(input){
 const original=input.plan;if(original?.version!==1||!original.commit||!original.reveal||!['refund','reveal'].includes(input.stage))fail('Choose recovery for the original Bitcoin commit.');
 const originalStage=original[input.stage],tx=unsignedCopy(originalStage),extra=input.inputs?.length?sourceInputs(input.inputs):[],r=rate(input.fee_rate),descriptors=[...originalStage.inputs,...extra.map(descriptor)];
 const existing=new Set(descriptors.slice(0,originalStage.inputs.length).map((_,i)=>{const v=tx.getInput(i);return hex.encode(v.txid)+':'+v.index;}));
 for(const u of extra){if(existing.has(u.txid+':'+u.index))fail('Duplicate recovery funding input.');existing.add(u.txid+':'+u.index);addInput(tx,u);}
 let total=originalStage.inputs.reduce((v,d)=>v+BigInt(d.amount),0n)+extra.reduce((v,u)=>v+u.amount,0n),stage;
 if(input.stage==='refund'){
  const fee=minerFee(estimate(tx,descriptors),r),returned=total-fee;if(returned<546n)fail('Add clean BTC or reduce the refund fee rate.');tx.updateOutput(0,{amount:returned});stage=exportPlan(tx,descriptors,fee);
 }else stage=finish(tx,descriptors,total,original.payment.address,r);
 return {...original,[input.stage]:stage,fee_rate:String(input.fee_rate)};
}
