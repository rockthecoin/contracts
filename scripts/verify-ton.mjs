import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {Cell} from '@ton/core';

const catalog=JSON.parse(fs.readFileSync('packages.json','utf8'));
let checked=0;
for(const pkg of catalog.ton){
 const lock=JSON.parse(fs.readFileSync(path.join(pkg.directory,'published.lock'),'utf8'));
 assert.equal(lock.package,pkg.id);assert.equal(lock.compiler,'@ton/tolk-js 1.5.0');
 for(const [name,expected] of Object.entries(lock.files)){
  assert(!path.isAbsolute(name)&&!name.split('/').includes('..'));
  assert.equal(createHash('sha256').update(fs.readFileSync(path.join(pkg.directory,name))).digest('hex'),expected,name);
 }
 const artifact=JSON.parse(fs.readFileSync(pkg.artifact,'utf8')),source=JSON.parse(fs.readFileSync(pkg.source,'utf8'));
 assert.equal(artifact.package,pkg.id);assert.equal(artifact.compiler,'Tolk 1.5.0');assert.equal(artifact.workchain,0);
 assert.deepEqual(source.artifacts,artifact);
 for(const [name,text] of Object.entries(source.sources)){
  assert.equal(fs.readFileSync(path.join(pkg.directory,name),'utf8'),text);
  assert.equal(createHash('sha256').update(text).digest('hex'),artifact.sources[name]);
 }
 assert.deepEqual(Object.keys(artifact.contracts).sort(),['JettonMaster','JettonWallet','NftCollection','NftItem','SuiteFactory','Vesting']);
 for(const [name,contract] of Object.entries(artifact.contracts)){
  assert.equal(Cell.fromBase64(contract.codeBoc).hash().toString('hex'),contract.codeHash);
  assert.equal(lock.contracts[name],contract.codeHash);checked++;
 }
}
console.log(JSON.stringify({verifiedTonContracts:checked,packages:catalog.ton.length,networkRequests:0,broadcasts:0}));
