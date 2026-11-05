// Offline integrity verification only; no wallet or network calls.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const sha=v=>createHash('sha256').update(v).digest('hex');
const packages=JSON.parse(fs.readFileSync('packages.json')).sui;
let modules=0,files=0;
for(const p of packages){
  const root=p.directory,artifact=JSON.parse(fs.readFileSync(p.artifact)),source=JSON.parse(fs.readFileSync(p.source)),lock=JSON.parse(fs.readFileSync(root+'/published.lock'));
  assert.equal(source.compiler,p.compiler);assert.equal(artifact.compiler,p.compiler);
  assert.equal(sha(fs.readFileSync(p.source)),lock.source_sha256);
  assert.equal(sha(fs.readFileSync(p.artifact)),lock.artifact_sha256);
  assert.equal(sha(JSON.stringify(source.sources)),source.source_digest);
  assert.equal(source.source_digest,artifact.source_digest);assert.equal(source.source_digest,lock.source_digest);
  function checkFiles(base,sources){for(const [name,text] of Object.entries(sources)){
    assert(!path.isAbsolute(name)&&!name.split('/').includes('..'));assert.equal(fs.readFileSync(base+'/'+name,'utf8'),text,base+'/'+name);files++;
  }}
  if(p.id==='sui-suite-v1'){
    assert.equal(source.framework_revision,p.framework_revision);
    for(const [group,sources] of Object.entries(source.sources))checkFiles(root+(group==='package'?'/package':'/templates/'+group),sources);
    assert.equal(Object.keys(artifact.modules).length,7);
    for(const [name,value] of Object.entries(artifact.modules)){assert.equal(sha(Buffer.from(value,'base64')),artifact.module_sha256[name]);modules++;}
    for(const v of Object.values(artifact.templates)){assert.equal(v.modules.length,1);assert.equal(sha(Buffer.from(v.modules[0],'base64')),v.sha256);modules++;}
  }else{
    checkFiles(root+'/collection',source.sources);assert.equal(artifact.modules.length,1);assert.equal(sha(Buffer.from(artifact.modules[0],'base64')),artifact.sha256);modules++;
  }
}
console.log(JSON.stringify({result:'passed',packages:packages.length,modules,source_files:files,network_requests:0,broadcasts:0}));
