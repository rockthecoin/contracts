import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {runTolkCompiler,getTolkCompilerVersion} from '@ton/tolk-js';
import {Cell} from '@ton/core';

const root=path.resolve('contracts/ton-suite-v2'),output=path.join(root,'artifacts'),verify=process.argv.includes('--verify');
if(fs.existsSync(path.join(root,'published.lock'))&&!verify)throw new Error('This TON release is frozen; reproduce with --verify or create a new version.');
const version=await getTolkCompilerVersion();if(version!=='1.5.0')throw new Error('Use pinned Tolk 1.5.0.');
const files=fs.readdirSync(root).filter(f=>f.endsWith('.tolk')).sort(),sources=Object.fromEntries(files.map(f=>[f,fs.readFileSync(path.join(root,f),'utf8')]));
const contracts={};
for(const name of ['SuiteFactory','JettonWallet','JettonMaster','NftItem','NftCollection','Vesting']){
 if(!fs.existsSync(path.join(root,name+'.tolk')))continue;
 const result=await runTolkCompiler({entrypointFileName:name+'.tolk',fsReadCallback:f=>{const target=path.resolve(root,f);if(!target.startsWith(root+'/'))throw new Error('Source outside release.');return fs.readFileSync(target,'utf8');}});
 if(result.status!=='ok')throw new Error(name+': '+result.message);
 const code=Cell.fromBase64(result.codeBoc64);contracts[name]={codeBoc:code.toBoc().toString('base64'),codeHash:code.hash().toString('hex'),abi:result.abiJson};console.log(name+': '+contracts[name].codeHash);
}
const hashes=Object.fromEntries(Object.entries(sources).map(([k,v])=>[k,crypto.createHash('sha256').update(v).digest('hex')]));
const artifact={version:2,package:'ton-suite-v2',compiler:'Tolk '+version,network:'mainnet',workchain:0,sources:hashes,contracts};
const body=JSON.stringify(artifact,null,2)+'\n',sourceBody=JSON.stringify({package:'ton-suite-v2',compiler:'@ton/tolk-js 1.5.0',sources,artifacts:artifact},null,2)+'\n';
if(verify){if(fs.readFileSync(path.join(output,'suite.json'),'utf8')!==body||fs.readFileSync(path.join(output,'source.json'),'utf8')!==sourceBody)throw new Error('Frozen TON artifacts do not reproduce.');const lock=path.join(root,'published.lock');if(fs.existsSync(lock))for(const[file,expected]of Object.entries(JSON.parse(fs.readFileSync(lock,'utf8')).files)){const target=path.resolve(root,file);if(!target.startsWith(root+'/')||crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex')!==expected)throw new Error('Frozen TON source changed: '+file);}console.log('Exact TON release reproduced.');}
else{fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'suite.json'),body);fs.writeFileSync(path.join(output,'source.json'),sourceBody);}
