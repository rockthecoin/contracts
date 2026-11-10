import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const root='contracts/bitcoin-protocol-v1',manifest=JSON.parse(fs.readFileSync(root+'/published.lock','utf8'));
assert.equal(manifest.version,1);assert.equal(manifest.network,'mainnet');
for(const[path,hash]of Object.entries(manifest.files)){
 assert(/^[a-zA-Z0-9/_.-]+$/.test(path)&&!path.includes('..'));
 assert.equal(crypto.createHash('sha256').update(fs.readFileSync(root+'/'+path)).digest('hex'),hash,'Changed Bitcoin release file: '+path);
}
const bundle=JSON.parse(fs.readFileSync(root+'/artifacts/source.json','utf8'));
for(const[path,source]of Object.entries(bundle.files))assert.equal(fs.readFileSync(root+'/'+path,'utf8'),source,'Bitcoin source bundle differs: '+path);
console.log('Bitcoin V1 source, pinned dependencies, tests and source bundle match the frozen release.');
