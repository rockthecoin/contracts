import test from 'node:test';
import assert from 'node:assert/strict';
import {artifact,fixture,authorize,configuration,hashArgs,event,expectSuccess,expectRevert,signer,OWNER,CREATOR,TREASURY,ALICE} from './helpers.mjs';

const factoryArtifact=artifact('contracts/launch-v8/artifacts/LaunchFactoryV8.json');
const tokenArtifact=artifact('contracts/launch-v8/artifacts/ConfigurableTokenV8.json');

test('Avalanche V8 binds creation and AVAX payment to the V8 domain, C-Chain, payer and exact configuration',async()=>{
  const f=await fixture(43114),factory=await f.deploy(factoryArtifact,[OWNER,TREASURY,signer.address]);
  const config=configuration({permitEnabled:true,votingEnabled:true});
  const allocations=[{beneficiary:CREATOR,amount:10000n,start:0n,cliff:0n,end:0n}],q=f.quote();
  const fields=[config,allocations],hash=hashArgs(factoryArtifact,'createToken',fields);
  const options={domain:'RockTheCoinLaunch',version:'8'};
  const signature=await authorize(f,factoryArtifact,factory,hash,q,options);
  const args=[...fields,q,signature],before=await f.balance(TREASURY);
  for(const value of [999n,1001n])expectRevert(await f.call(factory,factoryArtifact,'createToken',args,{value}));
  expectRevert(await f.call(factory,factoryArtifact,'createToken',args,{caller:ALICE,value:q.fee}));
  for(const mismatch of [{version:'7'},{chainId:1}]){
    const rejected=await authorize(f,factoryArtifact,factory,hash,q,{...options,...mismatch});
    expectRevert(await f.call(factory,factoryArtifact,'createToken',[...fields,q,rejected],{value:q.fee}));
  }
  expectRevert(await f.call(factory,factoryArtifact,'createToken',[{...config,symbol:'OTHER'},allocations,q,signature],{value:q.fee}));
  await f.putCode(TREASURY,'0x60006000fd');
  expectRevert(await f.call(factory,factoryArtifact,'createToken',args,{value:q.fee}));
  assert.equal(await f.read(factory,factoryArtifact,'usedReferences',[q.referenceId]),false);
  assert.equal(await f.balance(TREASURY),before);
  await f.putCode(TREASURY,'0x');
  const result=expectSuccess(await f.call(factory,factoryArtifact,'createToken',args,{value:q.fee}));
  const asset=event(result,factoryArtifact,'AssetCreated').asset;
  assert.equal(await f.read(asset,tokenArtifact,'balanceOf',[CREATOR]),10000n);
  assert.equal(await f.balance(TREASURY)-before,q.fee);
  assert.equal(await f.balance(factory),0n);
  expectRevert(await f.call(factory,factoryArtifact,'createToken',args,{value:q.fee}));
});
