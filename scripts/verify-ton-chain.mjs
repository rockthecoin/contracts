// Public mainnet reads only. This script has no signing or broadcast path.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {Address,Cell,Dictionary,loadTransaction} from '@ton/core';

const map=JSON.parse(fs.readFileSync('deployments.json','utf8')),network=map.networks.find(n=>n.slug==='ton');
assert(network,'TON deployment is not listed');
const entry=network.contracts[0],release=JSON.parse(fs.readFileSync(entry.artifact,'utf8'));
const endpoint=new URL(process.env.TON_RPC||'https://toncenter.com/api/v2/jsonRPC');assert.equal(endpoint.protocol,'https:');
const allowed=new Set(['getMasterchainInfo','getBlockHeader','getAddressInformation','getTransactions']);
let last=0;
async function rpc(method,params={}){
 assert(allowed.has(method),'Read-only RPC restriction');
 for(let attempt=0;attempt<3;attempt++){
  const delay=1300-(Date.now()-last);if(delay>0)await new Promise(resolve=>setTimeout(resolve,delay));last=Date.now();
  const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json','Cache-Control':'no-cache'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(15000)});
  if(response.status===429&&attempt<2){await new Promise(resolve=>setTimeout(resolve,3000*(attempt+1)));continue;}
  assert(response.ok,`TON RPC HTTP ${response.status}`);const body=await response.json();assert.equal(body.ok??true,true);assert(!body.error);return body.result;
 }
}
function transaction(record){
 assert(['raw.transaction','ext.transaction'].includes(record?.['@type']));assert(!record.emulated&&!record.simulation);assert.equal(typeof record.data,'string');
 const cell=Cell.fromBase64(record.data),tx=loadTransaction(cell.beginParse());
 assert.equal(cell.hash().toString('base64'),record.transaction_id.hash);assert.equal(String(tx.lt),record.transaction_id.lt);assert.equal(tx.now,record.utime);
 // Transaction TLB header: tag, account, LT, previous hash/LT, time,
 // outgoing count and two account statuses; messages are the next reference.
 const header=4+256+64+256+64+32+15+2+2,envelope=cell.beginParse().skip(header).loadRef().beginParse();
 const incoming=envelope.loadMaybeRef(),outgoing=[...envelope.loadDict(Dictionary.Keys.Uint(15),Dictionary.Values.Cell()).values()];envelope.endParse();assert.equal(outgoing.length,tx.outMessagesCount);
 const d=tx.description;assert.equal(d.type,'generic');assert(!d.aborted);assert.equal(d.computePhase.type,'vm');assert.equal(d.computePhase.exitCode,0);if(d.actionPhase)assert.equal(d.actionPhase.resultCode,0);
 return{cell,tx,incoming,outgoing};
}
const master=await rpc('getMasterchainInfo');assert.equal(master.init.file_hash,'XplPz01CXAps5qeSWUtxcyBfdAo5zVb1N979KLSKD24=');
const b=master.last,header=await rpc('getBlockHeader',{workchain:-1,shard:String(b.shard),seqno:b.seqno,root_hash:b.root_hash,file_hash:b.file_hash});
assert.equal(header.global_id,-239);assert.equal(header.id.root_hash,b.root_hash);assert.equal(header.id.file_hash,b.file_hash);assert(Math.abs(Date.now()/1000-header.gen_utime)<180);
const account=await rpc('getAddressInformation',{address:entry.address,seqno:b.seqno});
assert.equal(account.state,'active');assert.equal(account.block_id.seqno,b.seqno);assert.equal(account.block_id.root_hash,b.root_hash);assert.equal(account.block_id.file_hash,b.file_hash);
const artifact=release.contracts.SuiteFactory;assert.equal(Cell.fromBase64(account.code).hash().toString('hex'),artifact.codeHash);
const data=Cell.fromBase64(account.data).beginParse(),owner=data.loadAddress().toRawString();data.loadRef();const treasury=data.loadAddress().toRawString(),signer=data.loadUintBig(256).toString(16).padStart(64,'0'),paused=data.loadBit();
assert.equal(owner,entry.owner);assert.equal(treasury,entry.treasury);assert.equal(signer,entry.quote_signer_public_key);assert.equal(paused,false);
const factoryRows=await rpc('getTransactions',{address:entry.address,limit:50,archival:true});
const factoryRaw=factoryRows.find(r=>Buffer.from(r.transaction_id.hash,'base64').toString('hex')===entry.transaction_hash);assert(factoryRaw,'Original factory transaction is not in the returned archive window');
const deployed=transaction(factoryRaw),message=deployed.tx.inMessage;
assert.equal(deployed.tx.address,BigInt('0x'+Address.parse(entry.address).hash.toString('hex')));assert(deployed.tx.lt<=BigInt(account.last_transaction_id.lt));
assert.equal(message.info.type,'internal');assert.equal(message.info.src.toRawString(),owner);assert.equal(message.info.dest.toRawString(),entry.address);
assert(message.init.code.equals(Cell.fromBase64(artifact.codeBoc)));
const initial=message.init.data.beginParse();assert.equal(initial.loadAddress().toRawString(),owner);initial.loadRef();assert.equal(initial.loadAddress().toRawString(),treasury);assert.equal(initial.loadUintBig(256).toString(16).padStart(64,'0'),signer);assert.equal(initial.loadBit(),false);assert.equal(initial.loadBit(),false);initial.endParse();
const ownerRows=await rpc('getTransactions',{address:owner,limit:50,archival:true});
const ownerRaw=ownerRows.find(r=>Buffer.from(r.transaction_id.hash,'base64').toString('hex')===entry.owner_transaction_hash);assert(ownerRaw,'Original owner transaction is not in the returned archive window');
const sent=transaction(ownerRaw);assert.equal(sent.tx.address,BigInt('0x'+Address.parse(owner).hash.toString('hex')));
assert.equal(sent.outgoing.filter(cell=>cell.hash().equals(deployed.incoming.hash())).length,1,'Exact parent/child message hash');
const report={checked_at:new Date().toISOString(),network:'TON mainnet',native_coin:'Gram (GRAM), formerly Toncoin (TON)',masterchain:b.seqno,address:entry.address,package:entry.package,code_hash:artifact.codeHash,owner,treasury,quote_signer_public_key:signer,paused,owner_transaction_hash:entry.owner_transaction_hash,deployment_transaction_hash:entry.transaction_hash,deployment_lt:String(deployed.tx.lt),exact_runtime:true,exact_initialization:true,exact_parent_child_message:true,wallet_signatures:0,broadcasts:0};
const outputIndex=process.argv.indexOf('--output');if(outputIndex!==-1)fs.writeFileSync(process.argv[outputIndex+1],JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
