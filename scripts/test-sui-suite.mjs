import {suiCli} from './sui-toolchain.mjs';
// Native VM tests only. No wallet, network transaction or publication.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const cli=suiCli(),root='contracts/sui-suite-v1';
if(execFileSync(cli,['--version'],{encoding:'utf8'}).trim()!=='sui 1.81.1-e04cf9aa915c')throw new Error('Use the pinned Sui CLI.');
const work=fs.mkdtempSync(path.join(os.tmpdir(),'rtc-sui-tests-'));
function run(directory){execFileSync(cli,['move','test','--path',directory,'--build-env','mainnet','--silence-warnings'],{stdio:'inherit',timeout:300000});}
try{
  fs.cpSync(root,work,{recursive:true,filter:p=>!p.split(path.sep).includes('build')});
  run(work+'/package');
  for(const kind of ['coin','collection']){
    const file=work+'/templates/'+kind+'/sources/'+(kind==='coin'?'rtc_coin':'rtc_nft')+'.move';
    const values={QUOTE_ID:'b"01234567890123456789012345678901"',NAME:'b"Test"',SYMBOL:'b"TST"',DESCRIPTION:'b""',ICON_URL:'b"ipfs://icon"',IMAGE_URL:'b"ipfs://image"',METADATA_URI:'b"ipfs://metadata"',DECIMALS:'9',SUPPLY:'1000',MAXIMUM:kind==='coin'?'2000':'2',FLAGS:kind==='coin'?'63':'14',OWNER:'@0xa',RECIPIENT:'@0xa',ROYALTY_TO:'@0xa',ROYALTY:'250',ROYALTY_MAXIMUM:'1000',DELEGATES:'vector[@0xb]',MASKS:'vector[1]',ALLOCATIONS:'vector[@0xb]',AMOUNTS:'vector[100]',BENEFICIARIES:'vector[@0xb]',VEST_AMOUNTS:'vector[200]',STARTS:'vector[0]',CLIFFS:'vector[100]',ENDS:'vector[1000]'};
    fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace(/const (\w+): ([^=]+)= [^;]+;/g,(original,name,type)=>Object.hasOwn(values,name)?`const ${name}: ${type}= ${values[name]};`:original));
    run(work+'/templates/'+kind);
  }
}finally{fs.rmSync(work,{recursive:true,force:true});}
