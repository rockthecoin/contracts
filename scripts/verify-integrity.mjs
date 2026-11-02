import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

for(const line of fs.readFileSync('SHA256SUMS','utf8').trim().split('\n')){
  const [,hash,path]=/^([a-f0-9]{64})  (.+)$/.exec(line)??[];
  assert.ok(hash&&path&&!path.includes('..')&&!path.startsWith('/'),'Invalid manifest entry');
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex'),hash,`Changed published file: ${path}`);
}
const folder='contracts/solana-controller-v1';
const source=JSON.parse(fs.readFileSync(folder+'/artifacts/source.json','utf8'));
for(const [name,content] of Object.entries(source.files))assert.equal(fs.readFileSync(folder+'/'+name,'utf8'),content,`Solana source: ${name}`);
const artifact=JSON.parse(fs.readFileSync(folder+'/artifacts/controller.json','utf8'));
const elf=fs.readFileSync(folder+'/artifacts/rockthecoin_controller.so');
assert.deepEqual(elf,Buffer.from(artifact.elf_base64,'base64'));
assert.equal(elf.length,artifact.size);
assert.equal(crypto.createHash('sha256').update(elf).digest('hex'),artifact.sha256);
console.log('Published source, inputs, artifacts and Solana executable hashes match.');
