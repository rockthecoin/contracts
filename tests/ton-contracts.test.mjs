// Synthetic public test keys and balances only. Never fund a fixture address.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {Address,Cell,beginCell,contractAddress,toNano} from '@ton/core';
import {Blockchain,createShardAccount,internal} from '@ton/sandbox';
import {ed25519} from '@noble/curves/ed25519';

const release=JSON.parse(fs.readFileSync(new URL('../contracts/ton-suite-v2/artifacts/suite.json',import.meta.url)));
const config=JSON.parse(fs.readFileSync(new URL('./fixtures/ton-mainnet-config.json',import.meta.url)));
const seed=Buffer.alloc(32,74),publicKey=Buffer.from(ed25519.getPublicKey(seed));
const code=name=>Cell.fromBase64(release.contracts[name].codeBoc);
const ok=tx=>tx.description.type==='generic'&&!tx.description.aborted&&tx.description.computePhase.type==='vm'&&tx.description.computePhase.exitCode===0&&(!tx.description.actionPhase||tx.description.actionPhase.resultCode===0);
const header=(op,id)=>beginCell().storeUint(op,32).storeUint(id,64);

async function environment(){
 const vm=await Blockchain.create({config:Cell.fromBase64(config.config)});vm.now=1794220000;vm.verbosity={print:false,blockchainLogs:false,vmLogs:'none',debugLogs:false};
 const operator=await vm.treasury('operator'),creator=await vm.treasury('creator'),treasury=await vm.treasury('receiving-wallet'),other=await vm.treasury('other');
 const data=beginCell().storeAddress(operator.address).storeRef(beginCell().storeAddress(null).endCell()).storeAddress(treasury.address).storeBuffer(publicKey).storeBit(false).storeDict(null).endCell();
 const init={code:code('SuiteFactory'),data},factory=contractAddress(0,init);
 await vm.setShardAccount(factory,createShardAccount({...init,address:factory,balance:toNano('1')}));
 const send=(from,to,body,value='1')=>vm.sendMessage(internal({from,to,body,value:toNano(value),bounce:true}));
 const account=async address=>(await vm.getContract(address)).accountState;
 return{vm,operator,creator,treasury,other,factory,send,account};
}

// These cells follow the public Tolk structs in storage.tolk/messages.tolk.
function creation(f,kind='NftItem'){
 const quoteId=BigInt('0x'+'42'.repeat(32)),queryId=quoteId>>192n,deadline=f.vm.now+180,fee=toNano('0.1');
 const economics=beginCell().storeCoins(fee).storeCoins(0).storeCoins(kind==='JettonMaster'?1000000n:1n).storeCoins(toNano('0.1')).storeCoins(toNano('2')).storeCoins(toNano('0.2')).endCell();
 const identity=beginCell().storeAddress(f.factory).endCell();
 const configuration=beginCell().storeUint(quoteId,256).storeAddress(f.creator.address).storeAddress(f.treasury.address).storeUint(deadline,32).storeRef(economics).storeRef(identity).endCell();
 const receipts=beginCell().storeUint(0,64).storeAddress(null).storeUint(0,64).storeUint(0,64).endCell();
 const content=beginCell().storeUint(1,8).storeStringTail('https://example.com/fixture.json').endCell();let data;
 if(kind==='JettonMaster'){
  const controls=beginCell().storeAddress(f.creator.address).storeAddress(null).storeCoins(2000000n).storeCoins(0);
  for(const bit of [true,true,true,true,false,true,true])controls.storeBit(bit);
  controls.storeDict(null).storeRef(code('JettonWallet')).storeDict(null);
  data=beginCell().storeUint(0,8).storeCoins(0).storeRef(configuration).storeRef(content).storeRef(receipts).storeRef(controls.endCell()).endCell();
 }else if(kind==='NftCollection'){
  const controls=beginCell().storeAddress(f.creator.address).storeAddress(null).storeUint(5,64).storeBit(true).storeBit(false).storeBit(true).storeBit(true).storeUint(500,16).storeAddress(f.creator.address).storeDict(null).storeRef(code('NftItem')).storeDict(null).endCell();
  data=beginCell().storeUint(0,8).storeUint(0,64).storeRef(configuration).storeRef(content).storeRef(receipts).storeRef(controls).endCell();
 }else if(kind==='Vesting'){
  const schedule=beginCell().storeUint(0,8).storeAddress(f.other.address).storeAddress(null).storeUint(f.vm.now,32).storeUint(f.vm.now+10,32).storeUint(f.vm.now+100,32).storeCoins(toNano('1')).endCell();
  data=beginCell().storeUint(0,8).storeCoins(0).storeAddress(null).storeCoins(0).storeRef(configuration).storeRef(schedule).storeRef(receipts).endCell();
 }else{
  const details=beginCell().storeUint(0,64).storeAddress(null).storeAddress(f.creator.address).storeBit(true).storeBit(true).storeUint(0,64).endCell();
  data=beginCell().storeUint(0,8).storeAddress(f.creator.address).storeRef(configuration).storeRef(content).storeRef(receipts).storeRef(details).endCell();
 }
 const init={code:code(kind),data},asset=contractAddress(0,init);
 const endpoints=beginCell().storeAddress(f.factory).storeAddress(f.treasury.address).endCell();
 const template=beginCell().storeRef(init.code).storeRef(init.data).endCell();
 const terms=beginCell().storeUint(0x52544332,32).storeUint(quoteId,256).storeAddress(f.creator.address).storeUint(deadline,32).storeCoins(toNano(kind==='Vesting'?'3':'2')).storeRef(endpoints).storeRef(template).endCell();
 const signature=Buffer.from(ed25519.sign(terms.hash(),seed));
 const body=beginCell().storeUint(0x52544310,32).storeBuffer(signature).storeRef(terms).endCell();
 return{quoteId,queryId,fee,init,asset,terms,signature,body};
}
const payments=(r,address)=>r.transactions.filter(t=>t.inMessage?.info.type==='internal'&&t.inMessage.info.dest.equals(address)&&t.inMessage.info.value.coins===toNano('0.1'));

for(const kind of ['JettonMaster','NftItem','NftCollection'])test(`TON V2 ${kind} initializes through its signed factory and pays the native fee once`,async()=>{
 const f=await environment(),c=creation(f,kind),result=await f.send(f.creator.address,f.factory,c.body,'3');
 assert.ok(result.transactions.every(ok));assert.equal(payments(result,f.treasury.address).length,1);
 const state=await f.account(c.asset);assert.equal(state.type,'active');assert.ok(state.state.code.equals(code(kind)));assert.equal(state.state.data.beginParse().loadUint(8),2);
 const replay=await f.send(f.creator.address,f.factory,c.body,'3');assert.equal(payments(replay,f.treasury.address).length,0);
});

test('TON V2 factory binds signatures, payer and expiry before any child deployment or payment',async()=>{
 for(const failure of ['signature','payer','expiry']){
  const f=await environment(),c=creation(f);let body=c.body,from=f.creator.address;
  if(failure==='signature'){const signature=Buffer.from(c.signature);signature[0]^=1;body=beginCell().storeUint(0x52544310,32).storeBuffer(signature).storeRef(c.terms).endCell();}
  if(failure==='payer')from=f.other.address;if(failure==='expiry')f.vm.now+=181;
  const result=await f.send(from,f.factory,body,'3');assert.ok(result.transactions.some(t=>!ok(t)));assert.equal(payments(result,f.treasury.address).length,0);assert.notEqual((await f.account(c.asset))?.type,'active');
 }
});

test('TON V2 operator configuration requires its owner and cannot upgrade the factory code',async()=>{
 const f=await environment(),body=header(0x52544312,1n).storeAddress(f.other.address).storeBuffer(publicKey).storeBit(true).endCell();
 const forbidden=await f.send(f.other.address,f.factory,body);assert.ok(forbidden.transactions.some(t=>!ok(t)));
 const accepted=await f.send(f.operator.address,f.factory,body);assert.ok(accepted.transactions.every(ok));
 const state=await f.account(f.factory);assert.ok(state.state.code.equals(code('SuiteFactory')));
 const data=state.state.data.beginParse();assert.ok(data.loadAddress().equals(f.operator.address));data.loadRef();assert.ok(data.loadAddress().equals(f.other.address));data.loadUintBig(256);assert.equal(data.loadBit(),true);
 const c=creation(f),blocked=await f.send(f.creator.address,f.factory,c.body,'3');assert.equal(payments(blocked,f.treasury.address).length,0);
});

test('TON V2 collection mint binds the expected index and cannot mint another item on replay',async()=>{
 const f=await environment(),c=creation(f,'NftCollection');await f.send(f.creator.address,f.factory,c.body,'3');
 const content=beginCell().storeUint(1,8).storeStringTail('https://example.com/item.json').endCell();
 const request=header(0x52544330,55n).storeUint(0,64).storeAddress(f.creator.address).storeRef(content).endCell();
 const first=await f.send(f.creator.address,c.asset,request);assert.ok(first.transactions.every(ok));
 const readIndex=async()=>{const s=(await f.account(c.asset)).state.data.beginParse();s.loadUint(8);return s.loadUintBig(64);};assert.equal(await readIndex(),1n);
 await f.send(f.creator.address,c.asset,request);assert.equal(await readIndex(),1n);
});

test('TON V2 native vesting releases only vested principal to its fixed beneficiary',async()=>{
 const f=await environment(),c=creation(f,'Vesting'),launch=await f.send(f.creator.address,f.factory,c.body,'4');assert.ok(launch.transactions.every(ok));
 assert.equal(payments(launch,f.treasury.address).length,1);f.vm.now+=50;
 const release=await f.send(f.creator.address,c.asset,header(0x52544340,66n).endCell());assert.ok(release.transactions.every(ok));
 const payouts=release.transactions.filter(t=>t.inMessage?.info.type==='internal'&&t.inMessage.info.src.equals(c.asset)&&t.inMessage.info.dest.equals(f.other.address));
 assert.equal(payouts.length,1);assert.equal(payouts[0].inMessage.info.value.coins,toNano('0.5'));
 const state=(await f.account(c.asset)).state.data.beginParse();assert.equal(state.loadUint(8),2);assert.equal(state.loadCoins(),toNano('0.5'));
});
