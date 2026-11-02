import test from 'node:test';
import assert from 'node:assert/strict';
import {encodeAbiParameters,keccak256,encodeFunctionData} from 'viem';
import {artifact,fixture,authorize,expectSuccess,expectRevert,signer,OWNER,CREATOR,TREASURY,ALICE,BOB} from './helpers.mjs';

const toolsArtifact=artifact('contracts/tools-v1/artifacts/ServiceTools.json'),tokenArtifact=artifact('build/RockToken.json');
const operationHash=(method,args)=>{
  const fn=toolsArtifact.abi.find(x=>x.type==='function'&&x.name===method);
  return keccak256(encodeAbiParameters([{type:'uint8'},...fn.inputs.slice(0,-2)],[{sendNative:0,sendTokens:1,execute:2}[method],...args]));
};
async function setup(){
  const f=await fixture(),tools=await f.deploy(toolsArtifact,[OWNER,TREASURY,signer.address]);
  const token=await f.deploy(tokenArtifact,['Tools fixture','TOOL',0,10000n,CREATOR]);
  async function signed(method,args){const q=f.quote(),sig=await authorize(f,toolsArtifact,tools,operationHash(method,args),q,{domain:'RockTheCoinTools',version:'1',type:'OperationQuote'});return {q,args:[...args,q,sig]};}
  return {...f,tools,token,signed};
}
test('a failing multisender recipient rolls back all recipients, the fee and the quote reference',async()=>{
  const f=await setup(),s=await f.signed('sendNative',[[ALICE,BOB],[100n,200n]]),beforeAlice=await f.balance(ALICE),beforeTreasury=await f.balance(TREASURY);
  await f.putCode(BOB,'0x60006000fd');
  expectRevert(await f.call(f.tools,toolsArtifact,'sendNative',s.args,{value:s.q.fee+300n}));
  assert.equal(await f.balance(ALICE),beforeAlice);assert.equal(await f.balance(TREASURY),beforeTreasury);
  assert.equal(await f.read(f.tools,toolsArtifact,'usedReferences',[s.q.referenceId]),false);
  await f.putCode(BOB,'0x');
  expectSuccess(await f.call(f.tools,toolsArtifact,'sendNative',s.args,{value:s.q.fee+300n}));
  assert.equal(await f.balance(ALICE)-beforeAlice,100n);assert.equal(await f.balance(TREASURY)-beforeTreasury,s.q.fee);
  assert.equal(await f.balance(f.tools),0n);
});
test('token multisending requires the creator allowance and rolls back when service payment fails',async()=>{
  const f=await setup(),s=await f.signed('sendTokens',[f.token,[ALICE,BOB],[100n,200n]]);
  expectRevert(await f.call(f.tools,toolsArtifact,'sendTokens',s.args,{value:s.q.fee}));
  expectSuccess(await f.call(f.token,tokenArtifact,'approve',[f.tools,300n]));
  await f.putCode(TREASURY,'0x60006000fd');
  expectRevert(await f.call(f.tools,toolsArtifact,'sendTokens',s.args,{value:s.q.fee}));
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[ALICE]),0n);
  assert.equal(await f.read(f.token,tokenArtifact,'allowance',[CREATOR,f.tools]),300n);
  await f.putCode(TREASURY,'0x');
  expectSuccess(await f.call(f.tools,toolsArtifact,'sendTokens',s.args,{value:s.q.fee}));
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[ALICE]),100n);
  assert.equal(await f.read(f.token,tokenArtifact,'allowance',[CREATOR,f.tools]),0n);
});
test('protocol calls need owner-approved targets, protect existing token balances, refund unused input and clear allowances',async()=>{
  const f=await setup();
  expectSuccess(await f.call(f.token,tokenArtifact,'transfer',[f.tools,50n]));
  expectSuccess(await f.call(f.token,tokenArtifact,'approve',[f.tools,100n]));
  const calls=[{target:f.token,value:0n,data:encodeFunctionData({abi:tokenArtifact.abi,functionName:'transfer',args:[ALICE,60n]})}];
  const s=await f.signed('execute',[[{token:f.token,amount:100n}],calls,[]]);
  expectRevert(await f.call(f.tools,toolsArtifact,'execute',s.args,{value:s.q.fee}));
  expectRevert(await f.call(f.tools,toolsArtifact,'setAllowedTarget',[f.token,true]));
  expectSuccess(await f.call(f.tools,toolsArtifact,'setAllowedTarget',[f.token,true],{caller:OWNER}));
  expectSuccess(await f.call(f.tools,toolsArtifact,'execute',s.args,{value:s.q.fee}));
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[f.tools]),50n);
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[ALICE]),60n);
  assert.equal(await f.read(f.token,tokenArtifact,'allowance',[f.tools,f.token]),0n);
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[CREATOR]),9890n);
});
test('multiple native protocol calls cannot reuse one deposit to spend pre-existing funds',async()=>{
  const f=await setup();
  await f.putCode(ALICE,'0x00');
  const {createAddressFromString}=await import('@ethereumjs/util');
  const address=createAddressFromString(f.tools),account=await f.vm.stateManager.getAccount(address);account.balance=50n;await f.vm.stateManager.putAccount(address,account);
  expectSuccess(await f.call(f.tools,toolsArtifact,'setAllowedTarget',[ALICE,true],{caller:OWNER}));
  const s=await f.signed('execute',[[],[{target:ALICE,value:95n,data:'0x'},{target:ALICE,value:95n,data:'0x'}],[]]);
  const before=await f.balance(ALICE);
  expectRevert(await f.call(f.tools,toolsArtifact,'execute',s.args,{value:s.q.fee+95n}));
  assert.equal(await f.balance(f.tools),50n);assert.equal(await f.balance(ALICE),before);
  assert.equal(await f.read(f.tools,toolsArtifact,'usedReferences',[s.q.referenceId]),false);
  expectSuccess(await f.call(f.tools,toolsArtifact,'execute',s.args,{value:s.q.fee+190n}));
  assert.equal(await f.balance(f.tools),50n);assert.equal(await f.balance(ALICE)-before,190n);
});
