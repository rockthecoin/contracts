import {suiCli} from './sui-toolchain.mjs';
// Offline compilation only. Never publishes a package or signs a transaction.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import init,* as bytecode from '@mysten/move-bytecode-template';

const root='contracts/sui-suite-v1',cli=suiCli();
const compiler=execFileSync(cli,['--version'],{encoding:'utf8'}).trim();
if(compiler!=='sui 1.81.1-e04cf9aa915c')throw new Error('Use the pinned Sui CLI 1.81.1.');
const check=true;
if(fs.existsSync(root+'/published.lock')&&!check)throw new Error('The offered Sui release is frozen. Use --check or a new release directory.');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const placeholder='0x'+'7a'.repeat(32),work=fs.mkdtempSync(path.join(os.tmpdir(),'rtc-sui-suite-'));
await init();
function build(directory){
  const output=execFileSync(cli,['move','build','--path',directory,'--build-env','mainnet',
    '--dump-bytecode-as-base64','--with-unpublished-dependencies','--no-tree-shaking','--silence-warnings'],
    {encoding:'utf8',timeout:300000,maxBuffer:5000000});
  return JSON.parse(output.trim().split('\n').at(-1));
}
function moduleName(encoded){const m=bytecode.deserialize(Buffer.from(encoded,'base64'));return m.identifiers[m.module_handles[m.self_module_handle_idx].name];}
function files(directory){const out={};for(const entry of fs.readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){
  if(['build','.git'].includes(entry.name))continue;
  const current=path.join(directory,entry.name);
  if(entry.isDirectory()){for(const [name,value] of Object.entries(files(current)))out[entry.name+'/'+name]=value;}
  else if(entry.name.endsWith('.move')||['Move.toml','Move.lock'].includes(entry.name))out[entry.name]=fs.readFileSync(current,'utf8');
}return out;}
try{
  const core=path.join(work,'package');fs.cpSync(root+'/package',core,{recursive:true,filter:name=>!name.split(path.sep).includes('build')});
  const built=build(core),modules=Object.fromEntries(built.modules.map(encoded=>[moduleName(encoded),encoded]));
  const expected=['authority','coin_control','collection','distribution','object_lock','royalty','vesting'];
  if(JSON.stringify(Object.keys(modules).sort())!==JSON.stringify(expected))throw new Error('Unexpected Sui suite module list.');
  if(JSON.stringify(built.dependencies)!==JSON.stringify(['0x'+'1'.padStart(64,'0'),'0x'+'2'.padStart(64,'0')]))throw new Error('Unexpected Sui suite dependencies.');
  // Compile creator templates against an explicit placeholder for the already
  // published library. Only this address entry is replaced after registration.
  fs.writeFileSync(path.join(core,'Move.toml'),fs.readFileSync(path.join(core,'Move.toml'),'utf8').replace('rtc_suite = "0x0"','rtc_suite = "'+placeholder+'"'));
  const templates={};
  for(const kind of ['coin','collection']){
    const destination=path.join(work,'templates',kind);fs.mkdirSync(path.dirname(destination),{recursive:true});
    fs.cpSync(root+'/templates/'+kind,destination,{recursive:true,filter:name=>!name.split(path.sep).includes('build')});
    const result=build(destination);
    if(result.modules.length!==1||result.dependencies.length!==3||!result.dependencies.includes(placeholder))throw new Error('Unexpected creator package dependencies.');
    const raw=Buffer.from(result.modules[0],'base64');
    templates[kind]={modules:result.modules,dependencies:result.dependencies,sha256:sha(raw),constants:bytecode.get_constants(raw)};
  }
  // Lock files describe the offered original source, not its temporary address
  // substitution. Generate the original root's lock file through a normal build.
  if(!fs.existsSync(root+'/package/Move.lock'))build(root+'/package');
  const sources={package:files(root+'/package'),coin:files(root+'/templates/coin'),collection:files(root+'/templates/collection')};
  const sourceDigest=sha(JSON.stringify(sources));
  const artifact={version:1,compiler,framework_revision:'e04cf9aa915cb6c069092733bebc3648755998e2',
    template_library:'0.4.1',placeholder,dependencies:built.dependencies,modules,
    module_sha256:Object.fromEntries(Object.entries(modules).map(([name,encoded])=>[name,sha(Buffer.from(encoded,'base64'))])),
    templates,source_digest:sourceDigest};
  const encoded=JSON.stringify(artifact,null,2)+'\n';
  const sourceEncoded=JSON.stringify({version:1,compiler,framework_revision:artifact.framework_revision,source_digest:sourceDigest,sources},null,2)+'\n';
  if(check){
    if(fs.readFileSync(root+'/artifacts/suite.json','utf8')!==encoded)throw new Error('Sui suite artifacts differ from their pinned source.');
    if(fs.readFileSync(root+'/artifacts/source.json','utf8')!==sourceEncoded)throw new Error('Sui source download differs from its pinned source.');
    console.log('Reproduced the immutable Sui suite and both creator templates byte for byte.');
  }else{
    fs.mkdirSync(root+'/artifacts',{recursive:true});fs.writeFileSync(root+'/artifacts/suite.json',encoded);
    fs.writeFileSync(root+'/artifacts/source.json',sourceEncoded);
    console.log('Compiled '+expected.length+' native Sui modules and two creator templates; no deployment or signatures.');
  }
}finally{fs.rmSync(work,{recursive:true,force:true});}
