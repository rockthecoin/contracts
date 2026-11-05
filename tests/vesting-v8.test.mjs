import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import solc from 'solc-v838';
import {createVM} from '@ethereumjs/vm';
import {Common,Mainnet,Hardfork} from '@ethereumjs/common';
import {createBlock} from '@ethereumjs/block';
import {Account,createAddressFromString,hexToBytes,bytesToHex} from '@ethereumjs/util';
import {encodeDeployData,encodeFunctionData,decodeFunctionResult,toFunctionSelector} from 'viem';

const owner='0x'+'11'.repeat(20),beneficiary='0x'+'22'.repeat(20),caller='0x'+'33'.repeat(20),collector='0x'+'44'.repeat(20),addr=createAddressFromString;
const source=`pragma solidity 0.8.38;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract SurchargeFixture is ERC20 {
 address public escrow; address public collector; uint256 public bps; uint8 public mode=1; bool private probing; bytes4 public releaseReentry; bytes4 public surplusReentry;
 constructor(address holder) ERC20("Surcharge fixture","SF") {_mint(holder,10000);}
 function configure(address source,address receiver,uint256 rate) external {escrow=source;collector=receiver;bps=rate;}
 function setMode(uint8 value) external {mode=value;}
 function _probe(bytes4 selector) private returns(bytes4) {
  (bool ok,bytes memory result)=escrow.call(abi.encodePacked(selector));
  require(!ok&&result.length>=4,"Unexpected reentry result");return bytes4(result);
 }
 function _update(address from,address to,uint256 amount) internal override {
  if(from==escrow&&amount!=0&&mode==2){super._update(from,to,amount-amount*bps/10000);super._update(from,address(0),amount*bps/10000);return;}
  super._update(from,to,amount);
  if(from==escrow&&amount!=0&&bps!=0&&mode==1)super._update(from,collector,amount*bps/10000);
  if(from==escrow&&amount!=0&&mode==3)super._update(address(0),from,10);
  if(from==escrow&&amount!=0&&mode==4&&!probing){probing=true;releaseReentry=_probe(bytes4(keccak256("release()")));surplusReentry=_probe(bytes4(keccak256("releaseSurplus()")));probing=false;}
 }
}`;
const input={language:'Solidity',sources:{'SurchargeFixture.sol':{content:source}},settings:{optimizer:{enabled:true,runs:100},evmVersion:'cancun',outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}};
const frozenSources=JSON.parse(fs.readFileSync('contracts/launch-v8/artifacts/standard-input.json','utf8')).sources;
const output=JSON.parse(solc.compile(JSON.stringify(input),{import:p=>frozenSources[p]?{contents:frozenSources[p].content}:{error:'Source absent from frozen input: '+p}}));
assert.equal((output.errors||[]).filter(e=>e.severity==='error').length,0);
const compiled=output.contracts['SurchargeFixture.sol'].SurchargeFixture,tokenArtifact={abi:compiled.abi,bytecode:'0x'+compiled.evm.bytecode.object};
async function fixture(version,{chainId=43114,recipientIsToken=false,donation=0n,cliff=1000n,end=2000n}={}){
 const artifact=JSON.parse(fs.readFileSync('contracts/launch-v'+version+'/artifacts/VestingWalletV'+version+'.json'));
 const common=new Common({chain:{...Mainnet,chainId},hardfork:chainId===10?Hardfork.Osaka:Hardfork.Cancun}),vm=await createVM({common}),block=time=>createBlock({header:{timestamp:time,gasLimit:chainId===10?40000000n:80000000n}},{common});
 for(const a of [owner,beneficiary,caller,collector])await vm.stateManager.putAccount(addr(a),new Account(0n,10n**24n));
 async function deploy(a,args){const r=await vm.evm.runCall({caller:addr(owner),origin:addr(owner),data:hexToBytes(encodeDeployData({...a,args})),gasLimit:5000000n,block:block(1000n)});assert.equal(r.execResult.exceptionError,undefined);return r.createdAddress.toString();}
 const token=await deploy(tokenArtifact,[owner]),escrow=await deploy(artifact,[token,recipientIsToken?token:beneficiary,1000n,1000n,cliff,end]);
 async function call(to,abi,functionName,args=[],{account=owner,time=1250n}={}){return vm.evm.runCall({caller:addr(account),origin:addr(account),to:addr(to),data:hexToBytes(encodeFunctionData({abi,functionName,args})),gasLimit:2000000n,block:block(time)});}
 async function read(to,abi,functionName,args=[]){const r=await call(to,abi,functionName,args);assert.equal(r.execResult.exceptionError,undefined);return decodeFunctionResult({abi,functionName,data:bytesToHex(r.execResult.returnValue)});}
 assert.equal((await call(token,tokenArtifact.abi,'transfer',[escrow,1000n+donation])).execResult.exceptionError,undefined);
 return {tokenRead:name=>read(token,tokenArtifact.abi,name),send:(name,opts={})=>call(escrow,artifact.abi,name,[],opts),read:name=>read(escrow,artifact.abi,name),balance:a=>read(token,tokenArtifact.abi,'balanceOf',[a]),configure:rate=>call(token,tokenArtifact.abi,'configure',[escrow,collector,rate]),setMode:mode=>call(token,tokenArtifact.abi,'setMode',[mode]),token,escrow};
}
for(const [network,chainId] of [['Avalanche',43114]]){
test(network+' V7 reproduction: a permissionless partial release with a sender surcharge consumes unvested principal',async()=>{
 const f=await fixture(7,{chainId});await f.configure(1000n);
 assert.equal((await f.send('release',{account:caller})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),250n);assert.equal(await f.balance(f.escrow),725n);
 assert.equal(await f.balance(beneficiary),250n);assert.equal(await f.balance(collector),25n);
 assert.ok(await f.balance(f.escrow)<1000n-await f.read('released'));
});
test(network+' V7 reproduction: withdrawing donated surplus with a sender surcharge consumes locked principal before the cliff',async()=>{
 const f=await fixture(7,{chainId,donation:100n,cliff:2000n,end:3000n});await f.configure(1000n);
 assert.equal((await f.send('releaseSurplus',{account:beneficiary})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),0n);assert.equal(await f.balance(f.escrow),990n);
 assert.equal(await f.balance(collector),10n);assert.equal(await f.balance(beneficiary),100n);
});
test(network+' V8 rejects excess sender debits on permissionless partial releases and rolls back accounting and transfers',async()=>{
 const f=await fixture(8,{chainId});await f.configure(1000n);
 assert.ok((await f.send('release',{account:caller})).execResult.exceptionError);
 assert.equal(await f.read('released'),0n);assert.equal(await f.balance(f.escrow),1000n);
 assert.equal(await f.balance(beneficiary),0n);assert.equal(await f.balance(collector),0n);
 await f.configure(0n);assert.equal((await f.send('release',{account:caller})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),250n);assert.equal(await f.balance(f.escrow),750n);
 assert.equal((await f.send('release',{account:caller,time:2000n})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),1000n);assert.equal(await f.balance(beneficiary),1000n);
});
test(network+' V8 protects locked principal during surplus withdrawals and preserves cliff and beneficiary restrictions',async()=>{
 const f=await fixture(8,{chainId,donation:100n,cliff:2000n,end:3000n});await f.configure(1000n);
 assert.ok((await f.send('releaseSurplus',{account:beneficiary})).execResult.exceptionError);
 assert.equal(await f.balance(f.escrow),1100n);assert.equal(await f.balance(beneficiary),0n);assert.equal(await f.balance(collector),0n);assert.equal(await f.read('released'),0n);
 await f.configure(0n);assert.ok((await f.send('releaseSurplus',{account:caller})).execResult.exceptionError);
 assert.equal((await f.send('releaseSurplus',{account:beneficiary})).execResult.exceptionError,undefined);
 assert.equal(await f.balance(f.escrow),1000n);assert.equal(await f.balance(beneficiary),100n);
 assert.ok((await f.send('release',{account:caller,time:1999n})).execResult.exceptionError);
 assert.equal((await f.send('release',{account:caller,time:3000n})).execResult.exceptionError,undefined);
 assert.equal(await f.balance(beneficiary),1100n);assert.equal(await f.read('released'),1000n);
});
test(network+' V8 keeps recipient-side taxes as gross payouts without charging unvested principal',async()=>{
 const f=await fixture(8,{chainId});await f.configure(1000n);await f.setMode(2);
 assert.equal((await f.send('release',{account:caller})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),250n);assert.equal(await f.balance(f.escrow),750n);assert.equal(await f.balance(beneficiary),225n);
});
test(network+' V8 accepts a returned donation without treating it as an excessive sender debit',async()=>{
 const f=await fixture(8,{chainId});await f.configure(0n);await f.setMode(3);
 assert.equal((await f.send('release',{account:caller})).execResult.exceptionError,undefined);
 assert.equal(await f.read('released'),250n);assert.equal(await f.balance(f.escrow),760n);assert.equal(await f.balance(beneficiary),250n);
});

}
test('Avalanche V8 blocks both payout callbacks even when the hostile token is the beneficiary',async()=>{
 const f=await fixture(8,{chainId:43114,donation:100n,recipientIsToken:true});await f.configure(0n);await f.setMode(4);
 assert.equal((await f.send('release',{account:caller})).execResult.exceptionError,undefined);
 const guard=toFunctionSelector('ReentrancyGuardReentrantCall()');
 assert.equal(await f.tokenRead('releaseReentry'),guard);assert.equal(await f.tokenRead('surplusReentry'),guard);
 assert.equal((await f.read('beneficiary')).toLowerCase(),f.token.toLowerCase());assert.equal(await f.read('released'),250n);
 assert.equal(await f.balance(f.token),250n);assert.equal(await f.balance(f.escrow),850n);
});
