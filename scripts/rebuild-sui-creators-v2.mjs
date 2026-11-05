import {suiCli} from './sui-toolchain.mjs';
// Offline creator-template build. The deployed V1 library remains unchanged.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import init,* as bytecode from '@mysten/move-bytecode-template';
const root='contracts/sui-creators-v2',cli=suiCli(),check=true;
const compiler=execFileSync(cli,['--version'],{encoding:'utf8'}).trim();if(compiler!=='sui 1.81.1-e04cf9aa915c')throw new Error('Use the pinned Sui compiler.');
if(fs.existsSync(root+'/published.lock')&&!check)throw new Error('The Sui creator release is frozen.');
const hash=v=>createHash('sha256').update(v).digest('hex'),placeholder='0x'+'7a'.repeat(32),work=fs.mkdtempSync(path.join(os.tmpdir(),'rtc-sui-creators-'));
await init();
try{
 fs.cpSync('contracts/sui-suite-v1/package',work+'/sui-suite-v1/package',{recursive:true,filter:p=>!p.split(path.sep).includes('build')});
 const manifest=work+'/sui-suite-v1/package/Move.toml';fs.writeFileSync(manifest,fs.readFileSync(manifest,'utf8').replace('rtc_suite = "0x0"','rtc_suite = "'+placeholder+'"'));
 fs.cpSync(root+'/collection',work+'/sui-creators-v2/collection',{recursive:true,filter:p=>!p.split(path.sep).includes('build')});
 const output=execFileSync(cli,['move','build','--path',work+'/sui-creators-v2/collection','--build-env','mainnet','--dump-bytecode-as-base64','--with-unpublished-dependencies','--no-tree-shaking','--silence-warnings'],{encoding:'utf8',timeout:300000});
 const result=JSON.parse(output.trim().split('\n').at(-1));if(result.modules.length!==1||result.dependencies.length!==3||!result.dependencies.includes(placeholder))throw new Error('Unexpected Sui creator dependencies.');
 const sources=Object.fromEntries(['Move.toml','sources/rtc_nft.move','tests/creator_tests.move'].map(name=>[name,fs.readFileSync(root+'/collection/'+name,'utf8')]));
 const data={version:2,compiler,placeholder,source_digest:hash(JSON.stringify(sources)),modules:result.modules,dependencies:result.dependencies,sha256:hash(Buffer.from(result.modules[0],'base64')),constants:bytecode.get_constants(Buffer.from(result.modules[0],'base64'))};
 const artifacts={template:JSON.stringify(data,null,2)+'\n',source:JSON.stringify({version:2,compiler,source_digest:data.source_digest,sources},null,2)+'\n'};
 if(!check)fs.mkdirSync(root+'/artifacts',{recursive:true});
 for(const [kind,encoded] of Object.entries(artifacts)){const file=root+'/artifacts/'+kind+'.json';if(check){if(fs.readFileSync(file,'utf8')!==encoded)throw new Error('Creator artifact differs from source.');}else fs.writeFileSync(file,encoded);}
 console.log(check?'Reproduced Sui NFT creator V2.':'Compiled Sui NFT creator V2; no publication or signatures.');
}finally{fs.rmSync(work,{recursive:true,force:true});}
