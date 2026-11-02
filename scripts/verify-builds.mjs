// Compile in memory. Published artifacts are never regenerated or overwritten.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import solc30 from 'solc';
import solc38 from 'solc-v838';
import {keccak256} from 'viem';

const packages=JSON.parse(fs.readFileSync('packages.json','utf8'));
let verified=0;
for(const pkg of packages.evm){
  const compiler=pkg.compiler.startsWith('0.8.38+')?solc38:solc30;
  assert.equal(compiler.version(),pkg.compiler,`Compiler pin: ${pkg.id}`);
  const input=JSON.parse(fs.readFileSync(pkg.input,'utf8'));
  for(const [source,{content}] of Object.entries(input.sources)){
    const local=source==='RockTheCoinFactory.sol'?'contracts/'+source:source;
    if(local.startsWith('contracts/')){
      assert.equal(fs.readFileSync(local,'utf8'),content,`Source differs from saved input: ${source}`);
    }
  }
  const output=JSON.parse(compiler.compile(JSON.stringify(input)));
  const errors=(output.errors??[]).filter(e=>e.severity==='error');
  assert.equal(errors.length,0,errors.map(e=>e.formattedMessage).join('\n'));
  for(const entry of pkg.artifacts){
    const artifact=JSON.parse(fs.readFileSync(entry.path,'utf8'));
    const candidates=Object.values(output.contracts).flatMap(file=>Object.entries(file).filter(([name])=>name===entry.name).map(([,contract])=>contract));
    assert.equal(candidates.length,1,`Ambiguous artifact: ${entry.path}`);
    const compiled=candidates[0];
    assert.equal('0x'+compiled.evm.bytecode.object,artifact.bytecode,`Creation code: ${entry.path}`);
    assert.equal('0x'+compiled.evm.deployedBytecode.object,artifact.deployedBytecode,`Runtime: ${entry.path}`);
    assert.deepEqual(compiled.abi,artifact.abi,`ABI: ${entry.path}`);
    // AST node IDs can change with output selection; the grouped byte locations must match.
    const locations=refs=>Object.values(refs).map(group=>group.toSorted((a,b)=>a.start-b.start)).toSorted((a,b)=>a[0].start-b[0].start);
    if(artifact.immutableReferences)assert.deepEqual(locations(compiled.evm.deployedBytecode.immutableReferences),locations(artifact.immutableReferences),`Immutable locations: ${entry.path}`);
    const runtimeBytes=(artifact.deployedBytecode.length-2)/2;
    const creationBytes=(artifact.bytecode.length-2)/2;
    assert.ok(runtimeBytes<=24576,`EIP-170 size: ${entry.path}`);
    assert.ok(creationBytes<=49152,`EIP-3860 size: ${entry.path}`);
    console.log(JSON.stringify({package:pkg.id,contract:entry.name,compiler:pkg.compiler,creationBytes,runtimeBytes,runtimeHash:keccak256(artifact.deployedBytecode),reproduced:true}));
    verified++;
  }
}
console.log(JSON.stringify({verifiedArtifacts:verified,writes:0,rpcCalls:0,broadcasts:0}));
