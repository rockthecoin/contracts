// Native TVM compilation in memory; published files are never regenerated.
import fs from 'node:fs';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {execFileSync} from 'node:child_process';
const pin=JSON.parse(fs.readFileSync('toolchains/tron-solidity.json')),compiler=process.env.TRON_SOLC||'.toolchains/tron-solc',sha=x=>crypto.createHash('sha256').update(x).digest('hex');assert.equal(sha(fs.readFileSync(compiler)),pin.sha256,'Native TRON compiler pin');
const version=execFileSync(compiler,['--version'],{encoding:'utf8'});assert.match(version,/solc\.tron/);assert.ok(version.includes(pin.version));let count=0;
for(const pkg of JSON.parse(fs.readFileSync('packages.json')).tron){
 assert.equal(pkg.compiler_sha256,pin.sha256);const input=JSON.parse(fs.readFileSync(pkg.input));
 for(const [file,{content}] of Object.entries(input.sources))if(file.startsWith('contracts/'))assert.equal(fs.readFileSync(file,'utf8'),content,'Saved source '+file);
 assert.equal(input.settings.viaIR,true);assert.equal(input.settings.evmVersion,'cancun');assert.doesNotMatch(input.settings.optimizer.details.yulDetails.optimizerSteps,/[LE]/);
 const result=JSON.parse(execFileSync(compiler,['--standard-json'],{input:JSON.stringify(input),encoding:'utf8',maxBuffer:40_000_000}));assert.equal((result.errors||[]).filter(x=>x.severity==='error').length,0,JSON.stringify(result.errors));
 for(const entry of pkg.artifacts){
  const saved=JSON.parse(fs.readFileSync(entry.path)),compiled=result.contracts[saved.sourceName]?.[entry.name];assert.ok(compiled,'Unique saved contract '+entry.name);
  assert.equal('0x'+compiled.evm.bytecode.object,saved.bytecode,entry.path+' creation');assert.equal('0x'+compiled.evm.deployedBytecode.object,saved.deployedBytecode,entry.path+' runtime');assert.deepEqual(compiled.abi,saved.abi,entry.path+' ABI');assert.deepEqual(compiled.evm.deployedBytecode.immutableReferences,saved.immutableReferences,entry.path+' immutable bindings');count++;
 }
 console.log(pkg.id+': native TVM source, creation bytecode, runtime, ABI and immutable references reproduced.');
}
console.log(JSON.stringify({verifiedNativeArtifacts:count,publishedWrites:0,rpcCalls:0,broadcasts:0}));
