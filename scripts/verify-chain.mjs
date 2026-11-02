// Read-only EVM verification. No wallet, signing key or transaction RPC methods.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createPublicClient,http,keccak256} from 'viem';

const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1];};
const wanted=option('--chain');
const rpcConfig=option('--rpc-config')?JSON.parse(fs.readFileSync(option('--rpc-config'),'utf8')):null;
const manifest=JSON.parse(fs.readFileSync('deployments.json','utf8'));
const networks=manifest.networks.filter(c=>c.family==='evm'&&(!wanted||c.slug===wanted||String(c.chain_id)===wanted));
assert.ok(networks.length,'Choose an EVM network listed in deployments.json');
assert.ok(rpcConfig||option('--rpc')&&networks.length===1,'Provide --chain NAME --rpc URL or --rpc-config FILE');
const report={checked_at:new Date().toISOString(),method:'eth_getCode; immutable references masked only at compiler-declared locations',broadcasts:0,networks:[]};
for(const network of networks){
  const urls=rpcConfig?.[network.slug]?.rpc_urls??[option('--rpc')];
  let client,block;
  for(const url of urls){
    try{
      const candidate=createPublicClient({transport:http(url,{timeout:20000,retryCount:1})});
      assert.equal(await candidate.getChainId(),Number(network.chain_id),'RPC chain mismatch');
      block=await candidate.getBlockNumber();client=candidate;break;
    }catch{ /* Try another configured read endpoint without logging credentials. */ }
  }
  assert.ok(client,`No matching read endpoint available for ${network.slug}`);
  const result={network:network.slug,chain_id:Number(network.chain_id),block_number:String(block),contracts:[]};
  for(const deployment of network.contracts){
    const artifact=JSON.parse(fs.readFileSync(deployment.artifact,'utf8'));
    const code=(await client.getCode({address:deployment.address,blockNumber:block}))?.toLowerCase();
    assert.ok(code&&code!=='0x',`Missing code: ${network.slug}/${deployment.contract}`);
    assert.equal(code.length,artifact.deployedBytecode.length,`Runtime length: ${network.slug}/${deployment.contract}`);
    let normalized=code;
    const immutables={};
    for(const [id,references] of Object.entries(artifact.immutableReferences??{})){
      let value;
      for(const {start,length} of references){
        const next=code.slice(2+start*2,2+(start+length)*2);
        if(value!==undefined)assert.equal(next,value,`Inconsistent immutable ${id}`);
        value=next;
        normalized=normalized.slice(0,2+start*2)+'0'.repeat(length*2)+normalized.slice(2+(start+length)*2);
      }
      immutables[id]='0x'+value;
    }
    assert.equal(normalized,artifact.deployedBytecode.toLowerCase(),`Runtime mismatch: ${network.slug}/${deployment.contract}`);
    const state={};
    for(const functionName of ['owner','pendingOwner','treasury','quoteSigner','paused','poolManager','serviceTools','rewardsPaused']){
      if(!artifact.abi.some(x=>x.type==='function'&&x.name===functionName&&x.inputs.length===0))continue;
      state[functionName]=await client.readContract({address:deployment.address,abi:artifact.abi,functionName,blockNumber:block});
    }
    result.contracts.push({address:deployment.address,package:deployment.package,contract:deployment.contract,runtime_keccak256:keccak256(code),runtime_matches:true,immutable_values:immutables,state});
    console.error(`Matched ${network.slug}: ${deployment.contract} (${deployment.package})`);
  }
  report.networks.push(result);
}
const json=JSON.stringify(report,(_,value)=>typeof value==='bigint'?String(value):value,2)+'\n';
if(option('--output'))fs.writeFileSync(option('--output'),json);else process.stdout.write(json);
