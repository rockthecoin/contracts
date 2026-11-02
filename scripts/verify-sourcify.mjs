// Default: look up public source verification. --submit explicitly publishes saved compiler inputs.
// No credentials, wallets or blockchain transaction RPCs are used.
import fs from 'node:fs';
import assert from 'node:assert/strict';

const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1];};
const submit=args.includes('--submit'),wanted=option('--chain');
const manifest=JSON.parse(fs.readFileSync('deployments.json','utf8'));
const packages=JSON.parse(fs.readFileSync('packages.json','utf8')).evm;
const report={checked_at:new Date().toISOString(),provider:'Sourcify V2',blockchain_broadcasts:0,contracts:[]};
for(const network of manifest.networks.filter(c=>c.family==='evm'&&(!wanted||c.slug===wanted))){
  for(const deployment of network.contracts){
    const url=`https://sourcify.dev/server/v2/contract/${network.chain_id}/${deployment.address}`;
    const entry={network:network.slug,chain_id:Number(network.chain_id),address:deployment.address,package:deployment.package,contract:deployment.contract,source_url:`https://repo.sourcify.dev/${network.chain_id}/${deployment.address}`};
    let response=await fetch(url,{signal:AbortSignal.timeout(30000)}),data=await response.json();
    if(response.status===404&&submit){
      const pkg=packages.find(p=>p.id===deployment.package);assert.ok(pkg);
      const input=JSON.parse(fs.readFileSync(pkg.input,'utf8'));
      const sources=Object.entries(input.sources).filter(([,source])=>new RegExp('\\bcontract\\s+'+deployment.contract+'\\b').test(source.content));
      assert.equal(sources.length,1,`Contract identifier for ${deployment.contract}`);
      const body={stdJsonInput:input,compilerVersion:pkg.compiler.replace('.Emscripten.clang',''),contractIdentifier:sources[0][0]+':'+deployment.contract};
      const sent=await fetch(`https://sourcify.dev/server/v2/verify/${network.chain_id}/${deployment.address}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
      const submission=await sent.json();
      entry.submission_http_status=sent.status;
      if(submission.verificationId)entry.verification_id=submission.verificationId;
      else entry.submission_result=submission;
    }
    if(response.ok){
      for(const key of ['match','runtimeMatch','creationMatch','verifiedAt'])entry[key]=data[key]??null;
    }else{
      entry.status=response.status===404?'not_verified':'unavailable';
      entry.http_status=response.status;
    }
    report.contracts.push(entry);
    console.error(`${network.slug}: ${deployment.contract}: ${entry.match??(entry.verification_id?'submitted':entry.status)}`);
  }
}
const json=JSON.stringify(report,null,2)+'\n';
if(option('--output'))fs.writeFileSync(option('--output'),json);else process.stdout.write(json);
