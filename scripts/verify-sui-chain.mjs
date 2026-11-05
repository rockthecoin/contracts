// Read-only Sui mainnet verification. This tool has no signing or execution path.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {SuiGrpcClient} from '@mysten/sui/grpc';
import {Transaction,TransactionDataBuilder} from '@mysten/sui/transactions';
import {normalizeSuiAddress} from '@mysten/sui/utils';
import init,* as bytecode from '@mysten/move-bytecode-template';
const map=JSON.parse(fs.readFileSync('deployments.json'));
const network=map.networks.find(n=>n.slug==='sui');assert(network,'No published Sui deployment');
const deployment=network.contracts[0],artifact=JSON.parse(fs.readFileSync(deployment.artifact));
const url=process.env.SUI_RPC||'https://fullnode.mainnet.sui.io';assert(new URL(url).protocol==='https:','HTTPS RPC required');
const allowed=new Set(['GetServiceInfo','GetObject','GetTransaction']);
const client=new SuiGrpcClient({network:'mainnet',baseUrl:url,fetch:(input,options)=>{
  const target=new URL(typeof input==='string'?input:input.url??String(input));
  assert.equal(target.origin,new URL(url).origin);assert(allowed.has(target.pathname.split('/').at(-1)),'Read-only RPC restriction');
  return fetch(input,options);
}});
const {response:info}=await client.ledgerService.getServiceInfo({}, {timeout:15000});
assert.equal(info.chainId,network.chain_id);assert(Math.abs(Number(info.timestamp.seconds)-Date.now()/1000)<180,'Stale mainnet checkpoint');
const {response:objectResponse}=await client.ledgerService.getObject({objectId:deployment.address,readMask:{paths:['object_id','version','object_type','previous_transaction','package']}},{timeout:15000});
const object=objectResponse.object;assert.equal(object.objectId,deployment.address);assert.equal(object.objectType,'package');assert.equal(String(object.version),'1');assert.equal(object.previousTransaction,deployment.publication_transaction);
const pkg=object.package;assert(pkg);assert.equal(pkg.originalId??object.objectId,object.objectId);assert.equal(pkg.modules.length,7);
await init();const hashes={};
for(const m of pkg.modules){
 assert(Object.hasOwn(artifact.modules,m.name));assert(!Object.hasOwn(hashes,m.name),'Duplicate module');
 const module=bytecode.deserialize(m.contents),self=module.module_handles[module.self_module_handle_idx];
 assert.equal('0x'+module.address_identifiers[self.address],deployment.address);assert.equal(module.identifiers[self.name],m.name);
 module.address_identifiers=module.address_identifiers.map(a=>'0x'+a===deployment.address?'0'.repeat(64):a);
 const code=bytecode.serialize(module);assert.equal(Buffer.from(code).toString('base64'),artifact.modules[m.name],m.name);
 hashes[m.name]=createHash('sha256').update(code).digest('hex');assert.equal(hashes[m.name],artifact.module_sha256[m.name]);
}
assert.deepEqual(pkg.linkage.map(l=>l.originalId).sort(),[...artifact.dependencies].sort());
for(const l of pkg.linkage)assert.equal(l.originalId,l.upgradedId);
const {response:txResponse}=await client.ledgerService.getTransaction({digest:deployment.publication_transaction,readMask:{paths:['digest','transaction.bcs','effects','checkpoint','timestamp','objects.objects.object_id','objects.objects.version','objects.objects.digest','objects.objects.owner','objects.objects.object_type']}},{timeout:15000});
const tx=txResponse.transaction;assert.equal(tx.digest,deployment.publication_transaction);assert.equal(tx.effects.status.success,true);assert.equal(String(tx.checkpoint),deployment.publication_checkpoint);
const raw=tx.transaction.bcs.value;assert.equal(TransactionDataBuilder.getDigestFromBytes(raw),tx.digest);
const data=Transaction.from(raw).getData();assert.equal(data.sender,deployment.publishing_wallet);
const index=data.commands.findIndex(c=>c.$kind==='Publish');assert([0,3].includes(index));assert.equal(data.commands.length,index+2);
assert.deepEqual(data.commands[index].Publish.modules,Object.values(artifact.modules));
assert.deepEqual(data.commands[index].Publish.dependencies.map(value=>normalizeSuiAddress(value)),artifact.dependencies);
const call=data.commands[index+1].MoveCall;assert.equal(normalizeSuiAddress(call.package),normalizeSuiAddress('0x2'));assert.equal(call.module,'package');assert.equal(call.function,'make_immutable');assert.deepEqual(call.typeArguments,[]);assert.equal(call.arguments.length,1);assert.equal(call.arguments[0].$kind,'Result');assert.equal(call.arguments[0].Result,index);
if(index===3){
 const prefix=['0x2::clock::timestamp_ms','0x1::u64::checked_sub','0x1::option::destroy_some'];
 for(let i=0;i<3;i++){const c=data.commands[i].MoveCall;assert(c);assert.equal(normalizeSuiAddress(c.package)+'::'+c.module+'::'+c.function,normalizeSuiAddress(prefix[i].split('::')[0])+'::'+prefix[i].split('::').slice(1).join('::'));}
}
const created=tx.objects.objects.filter(o=>o.objectType==='package'&&o.objectId===deployment.address);assert.equal(created.length,1);assert.equal(created[0].owner.kind,4);
assert(tx.effects.changedObjects.some(c=>c.objectId===deployment.address&&c.inputState===1&&c.idOperation===2&&[2,3].includes(c.outputState)&&String(c.outputVersion)==='1'&&c.outputDigest===created[0].digest));
console.log(JSON.stringify({checked_at:new Date().toISOString(),result:'passed',chain:'sui:mainnet',package:deployment.address,publishing_wallet:data.sender,publication_transaction:tx.digest,publication_checkpoint:String(tx.checkpoint),current_checkpoint:String(info.checkpointHeight),immutable:true,upgrade_cap_consumed_in_publication:true,exact_module_matches:hashes,source_digest:artifact.source_digest,read_only:true,broadcasts:0},null,2));
