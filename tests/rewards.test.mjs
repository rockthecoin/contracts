import test from 'node:test';
import assert from 'node:assert/strict';
import solc from 'solc';
import {encodeDeployData,getCreate2Address,keccak256,encodeAbiParameters,zeroAddress} from 'viem';
import {artifact,fixture,expectSuccess,expectRevert,signer,OWNER,CREATOR,TREASURY,ALICE,BOB} from './helpers.mjs';

const deployerArtifact=artifact('contracts/rewards-v1/artifacts/HookDeployer.json');
const tokenArtifact=artifact('build/RockToken.json');
const source=`// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
interface Token {function transfer(address,uint256) external returns(bool);}
contract TestManager {receive() external payable {} function take(address currency,address to,uint256 amount) external {if(currency==address(0)){(bool ok,)=to.call{value:amount}("");require(ok);}else require(Token(currency).transfer(to,amount));}}
`;
const output=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources:{'TestManager.sol':{content:source}},settings:{evmVersion:'cancun',optimizer:{enabled:true,runs:200},outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}})));
const compiled=output.contracts['TestManager.sol'].TestManager,managerArtifact={abi:compiled.abi,bytecode:'0x'+compiled.evm.bytecode.object};
async function setup(version){
  const f=await fixture(),hookArtifact=artifact(`contracts/rewards-v${version}/artifacts/CreatorRewardsHook.json`);
  const manager=await f.deploy(managerArtifact),tools=await f.deploy(managerArtifact),deployer=await f.deploy(deployerArtifact,[OWNER]);
  const bytecode=encodeDeployData({...hookArtifact,args:[manager,tools,OWNER,signer.address]});
  const bytecodeHash=keccak256(bytecode);
  let salt,hook;
  for(let i=0;;i++){
    salt='0x'+i.toString(16).padStart(64,'0');hook=getCreate2Address({from:deployer,salt,bytecodeHash});
    if((BigInt(hook)&16383n)===8260n)break;
    assert.ok(i<1000000,'CREATE2 test mining bound');
  }
  expectSuccess(await f.call(deployer,deployerArtifact,'deploy',[salt,bytecode],{caller:OWNER}));
  const token=await f.deploy(tokenArtifact,['Reward fixture','RWD',0,1000000n,manager]);
  const key={currency0:zeroAddress,currency1:token,fee:3000,tickSpacing:60,hooks:hook};
  const poolId=keccak256(encodeAbiParameters([hookArtifact.abi.find(x=>x.name==='registerPool').inputs[0]],[key]));
  const registration={poolId,creator:CREATOR,recipient:ALICE,feeBps:100,maximumFeeBps:200,feeMutable:true,recipientMutable:true,expiresAt:1180n,referenceId:f.quote().referenceId};
  const signature=await signer.signTypedData({domain:{name:'RockTheCoinRewards',version:'1',chainId:1,verifyingContract:hook},primaryType:'Registration',types:{Registration:[{name:'poolId',type:'bytes32'},{name:'creator',type:'address'},{name:'recipient',type:'address'},{name:'feeBps',type:'uint16'},{name:'maximumFeeBps',type:'uint16'},{name:'feeMutable',type:'bool'},{name:'recipientMutable',type:'bool'},{name:'expiresAt',type:'uint256'},{name:'referenceId',type:'bytes32'}]},message:registration});
  return {...f,hook,hookArtifact,manager,tools,token,key,poolId,registration,signature};
}
for(const version of [1,2,3])test(`rewards V${version}: registration is authorized, fee ceilings and freeze settings are permanent, and claims belong to the credited recipient`,async()=>{
  const f=await setup(version),a=f.hookArtifact;
  expectRevert(await f.call(f.hook,a,'registerPool',[f.key,f.registration,f.signature]));
  expectSuccess(await f.call(f.hook,a,'registerPool',[f.key,f.registration,f.signature],{caller:f.tools}));
  expectRevert(await f.call(f.hook,a,'registerPool',[f.key,f.registration,f.signature],{caller:f.tools}));
  expectRevert(await f.call(f.hook,a,'configurePool',[f.poolId,ALICE,201,false,false]));
  expectRevert(await f.call(f.hook,a,'configurePool',[f.poolId,BOB,150,false,false],{caller:OWNER}));
  expectSuccess(await f.call(f.hook,a,'configurePool',[f.poolId,ALICE,150,true,true]));
  expectRevert(await f.call(f.hook,a,'configurePool',[f.poolId,ALICE,100,false,false]));
  expectRevert(await f.call(f.hook,a,'configurePool',[f.poolId,BOB,150,false,false]));
  const delta=BigInt.asIntN(256,(BigInt.asUintN(128,-10000n)<<128n)|10000n),params={zeroForOne:true,amountSpecified:-10000n,sqrtPriceLimitX96:1n};
  expectRevert(await f.call(f.hook,a,'afterSwap',[CREATOR,f.key,params,delta,'0x']));
  expectSuccess(await f.call(f.hook,a,'afterSwap',[CREATOR,f.key,params,delta,'0x'],{caller:f.manager}));
  assert.equal(await f.read(f.hook,a,'claimable',[ALICE,f.token]),150n);
  expectRevert(await f.call(f.hook,a,'claim',[f.token,BOB],{caller:BOB}));
  expectSuccess(await f.call(f.hook,a,'setRewardsPaused',[true],{caller:OWNER}));
  expectSuccess(await f.call(f.hook,a,'afterSwap',[CREATOR,f.key,params,delta,'0x'],{caller:f.manager}));
  assert.equal(await f.read(f.hook,a,'claimable',[ALICE,f.token]),150n);
  expectSuccess(await f.call(f.hook,a,'claim',[f.token,ALICE],{caller:ALICE}));
  assert.equal(await f.read(f.token,tokenArtifact,'balanceOf',[ALICE]),150n);
  assert.equal(await f.read(f.hook,a,'claimable',[ALICE,f.token]),0n);
});
