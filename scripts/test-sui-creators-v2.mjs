import {suiCli} from './sui-toolchain.mjs';
// Native VM only: no wallet, funded signature or network transaction.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const cli=suiCli();
if(execFileSync(cli,['--version'],{encoding:'utf8'}).trim()!=='sui 1.81.1-e04cf9aa915c')throw new Error('Use the pinned Sui CLI.');
const work=fs.mkdtempSync(path.join(os.tmpdir(),'rtc-sui-creator-tests-'));
try{
 fs.cpSync('contracts/sui-suite-v1/package',work+'/sui-suite-v1/package',{recursive:true,filter:p=>!p.split(path.sep).includes('build')});
 fs.cpSync('contracts/sui-creators-v2/collection',work+'/sui-creators-v2/collection',{recursive:true,filter:p=>!p.split(path.sep).includes('build')});
 const file=work+'/sui-creators-v2/collection/sources/rtc_nft.move',values={QUOTE_ID:'b"01234567890123456789012345678901"',NAME:'b"Test"',SYMBOL:'b"TST"',DESCRIPTION:'b""',IMAGE_URL:'b"ipfs://image"',METADATA_URI:'b"ipfs://metadata"',MAXIMUM:'2',FLAGS:'14',OWNER:'@0xa',RECIPIENT:'@0xa',ROYALTY_TO:'@0xa',ROYALTY:'250',ROYALTY_MAXIMUM:'1000',DELEGATES:'vector[@0xb]',MASKS:'vector[1]',INITIAL_MINT:'1',INITIAL_FROZEN:'0'};
 fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace(/const (\w+): ([^=]+)= [^;]+;/g,(original,name,type)=>Object.hasOwn(values,name)?`const ${name}: ${type}= ${values[name]};`:original));
 execFileSync(cli,['move','test','--path',work+'/sui-creators-v2/collection','--build-env','mainnet','--silence-warnings'],{stdio:'inherit',timeout:300000});
}finally{fs.rmSync(work,{recursive:true,force:true});}
