import test from 'node:test';
import assert from 'node:assert/strict';
import {getContractAddress} from 'viem';
import {createAddressFromString} from '@ethereumjs/util';
import {artifact,fixture,authorize,configuration,hashArgs,event,expectSuccess,expectRevert,signer,OWNER,CREATOR,TREASURY,ALICE,BOB,ZERO} from './helpers.mjs';

const basic=artifact('build/RockTheCoinFactory.json'),token=artifact('build/RockToken.json');
const collectionFactory=artifact('contracts/collections-v1/artifacts/CollectionFactory.json'),collection=artifact('contracts/collections-v1/artifacts/NFTCollection.json');
for(const [network,chainId] of [['Ethereum',1],['BNB Chain',56],['Base',8453],['Polygon',137],['Arbitrum One',42161],['Avalanche',43114]]){
  test(`${network}: token creation binds the payer, chain, asset and exact fee; payment failure rolls everything back`,async()=>{
    const f=await fixture(chainId),factory=await f.deploy(basic,[OWNER,TREASURY,signer.address]);
    const fields=['Public token','PUB',9,10000n],q=f.quote(),hash=hashArgs(basic,'createToken',fields),signature=await authorize(f,basic,factory,hash,q);
    const args=[...fields,q,signature],before=await f.balance(TREASURY);
    for(const value of [999n,1001n])expectRevert(await f.call(factory,basic,'createToken',args,{value}));
    expectRevert(await f.call(factory,basic,'createToken',args,{caller:ALICE,value:1000n}));
    expectRevert(await f.call(factory,basic,'createToken',['Changed',...args.slice(1)],{value:1000n}));
    const wrongChain=await authorize(f,basic,factory,hash,q,{chainId:chainId===1?56:1});
    expectRevert(await f.call(factory,basic,'createToken',[...fields,q,wrongChain],{value:1000n}));
    await f.putCode(TREASURY,'0x60006000fd');
    expectRevert(await f.call(factory,basic,'createToken',args,{value:1000n}));
    assert.equal(await f.read(factory,basic,'usedReferences',[q.referenceId]),false);
    assert.equal(await f.balance(TREASURY),before);
    await f.putCode(TREASURY,'0x');
    const result=expectSuccess(await f.call(factory,basic,'createToken',args,{value:1000n}));
    const created=event(result,basic,'AssetCreated');
    assert.equal(await f.read(created.asset,token,'balanceOf',[CREATOR]),10000n);
    assert.equal(await f.read(created.asset,token,'decimals'),9);
    assert.equal(await f.balance(TREASURY)-before,1000n);
    assert.equal(await f.balance(factory),0n);
    expectRevert(await f.call(factory,basic,'createToken',args,{value:1000n}));
  });
}
test('factory ownership is separate from creator assets; only the factory owner can pause or rotate the signer',async()=>{
  const f=await fixture(),factory=await f.deploy(basic,[OWNER,TREASURY,signer.address]);
  expectRevert(await f.call(factory,basic,'setConfiguration',[TREASURY,ALICE]));
  expectRevert(await f.call(factory,basic,'setPaused',[true]));
  const fields=['Paused token','PAUSE',0,100n],q=f.quote(),sig=await authorize(f,basic,factory,hashArgs(basic,'createToken',fields),q);
  expectSuccess(await f.call(factory,basic,'setPaused',[true],{caller:OWNER}));
  expectRevert(await f.call(factory,basic,'createToken',[...fields,q,sig],{value:q.fee}));
  expectSuccess(await f.call(factory,basic,'setPaused',[false],{caller:OWNER}));
  expectSuccess(await f.call(factory,basic,'setConfiguration',[TREASURY,ALICE],{caller:OWNER}));
  expectRevert(await f.call(factory,basic,'createToken',[...fields,q,sig],{value:q.fee}));
});
test('collection minting remains creator-only, enforces a lifetime cap and supports two-step ownership and permanent closure',async()=>{
  const f=await fixture(),factory=await f.deploy(collectionFactory,[OWNER,TREASURY,signer.address]);
  const config={name:'Public collection',symbol:'NFT',uri:'ipfs://collection',maxSupply:2n,royaltyReceiver:CREATOR,royaltyBps:500},q=f.quote();
  const sig=await authorize(f,collectionFactory,factory,hashArgs(collectionFactory,'createCollection',[config]),q,{domain:'RockTheCoinCollections',version:'1',type:'CollectionQuote'});
  const result=expectSuccess(await f.call(factory,collectionFactory,'createCollection',[config,q,sig],{value:q.fee})),address=event(result,collectionFactory,'CollectionCreated').collection;
  assert.equal(await f.read(address,collection,'owner'),CREATOR);
  const mint=([who],id)=>f.call(address,collection,'mintBatch',[[who],['ipfs://item'],id]);
  const ref=()=>f.quote().referenceId;
  expectRevert(await f.call(address,collection,'mintBatch',[[ALICE],['ipfs://item'],ref()],{caller:OWNER}));
  expectSuccess(await mint([ALICE],ref()));expectSuccess(await mint([BOB],ref()));
  expectSuccess(await f.call(address,collection,'burn',[1n],{caller:ALICE}));
  expectRevert(await mint([ALICE],ref()));
  expectSuccess(await f.call(address,collection,'transferOwnership',[BOB]));
  assert.equal(await f.read(address,collection,'owner'),CREATOR);
  expectRevert(await f.call(address,collection,'acceptOwnership',[],{caller:ALICE}));
  expectSuccess(await f.call(address,collection,'acceptOwnership',[],{caller:BOB}));
  expectRevert(await f.call(address,collection,'closeMinting'));
  expectSuccess(await f.call(address,collection,'closeMinting',[],{caller:BOB}));
  assert.equal(await f.read(address,collection,'mintingClosed'),true);
});
for(const version of [6,7,8]){
  const factoryArtifact=artifact(`contracts/launch-v${version}/artifacts/LaunchFactoryV${version}.json`),tokenArtifact=artifact(`contracts/launch-v${version}/artifacts/ConfigurableTokenV${version}.json`);
  test(`V${version}: delegated minting obeys a permanent lifetime cap and paused ownership cannot be renounced`,async()=>{
    const f=await fixture(),factory=await f.deploy(factoryArtifact,[OWNER,TREASURY,signer.address]);
    const config=configuration({administrator:CREATOR,mintable:true,pausable:true,maximumSupply:11000n,lifetimeCap:true,roles:[{account:ALICE,mask:1}]}),allocations=[{beneficiary:CREATOR,amount:10000n,start:0n,cliff:0n,end:0n}],q=f.quote();
    const signature=await authorize(f,factoryArtifact,factory,hashArgs(factoryArtifact,'createToken',[config,allocations]),q,{domain:'RockTheCoinLaunch',version:String(version)});
    const created=event(expectSuccess(await f.call(factory,factoryArtifact,'createToken',[config,allocations,q,signature],{value:q.fee})),factoryArtifact,'AssetCreated').asset;
    expectRevert(await f.call(created,tokenArtifact,'mint',[BOB,1n],{caller:BOB}));
    expectSuccess(await f.call(created,tokenArtifact,'mint',[ALICE,1000n],{caller:ALICE}));
    expectSuccess(await f.call(created,tokenArtifact,'burn',[1000n],{caller:ALICE}));
    expectRevert(await f.call(created,tokenArtifact,'mint',[ALICE,1n],{caller:ALICE}));
    expectSuccess(await f.call(created,tokenArtifact,'setPaused',[true]));
    expectRevert(await f.call(created,tokenArtifact,'transfer',[BOB,1n]));
    expectRevert(await f.call(created,tokenArtifact,'renounceOwnership'));
    assert.equal(await f.read(created,tokenArtifact,'owner'),CREATOR);
  });
}
test('V7 vesting tolerates prefunded escrow dust and protects the immutable allocation until its cliff',async()=>{
  const f=await fixture(),factoryArtifact=artifact('contracts/launch-v7/artifacts/LaunchFactoryV7.json'),vesting=artifact('contracts/launch-v7/artifacts/VestingWalletV7.json');
  const factory=await f.deploy(factoryArtifact,[OWNER,TREASURY,signer.address]),asset=await f.deploy(token,['Vesting','VEST',0,10000n,CREATOR]);
  const fields=[asset,ALICE,1000n,1000n,1200n,2000n],q=f.quote();
  const sig=await authorize(f,factoryArtifact,factory,hashArgs(factoryArtifact,'createVesting',fields),q,{kind:1,domain:'RockTheCoinLaunch',version:'7'});
  const nextNonce=(await f.vm.stateManager.getAccount(createAddressFromString(factory))).nonce;
  const predicted=getContractAddress({from:factory,nonce:nextNonce});
  expectSuccess(await f.call(asset,token,'transfer',[predicted,7n]));
  expectSuccess(await f.call(asset,token,'approve',[factory,1000n]));
  const result=expectSuccess(await f.call(factory,factoryArtifact,'createVesting',[...fields,q,sig],{value:q.fee})),lock=event(result,factoryArtifact,'LockCreated').lock;
  assert.equal(lock.toLowerCase(),predicted.toLowerCase());
  expectRevert(await f.call(lock,vesting,'release',[],{time:1199n}));
  expectRevert(await f.call(lock,vesting,'releaseSurplus'));
  expectSuccess(await f.call(lock,vesting,'releaseSurplus',[],{caller:ALICE}));
  assert.equal(await f.read(asset,token,'balanceOf',[lock]),1000n);
  expectSuccess(await f.call(lock,vesting,'release',[],{time:1500n}));
  assert.equal(await f.read(asset,token,'balanceOf',[ALICE]),507n);
  expectSuccess(await f.call(lock,vesting,'release',[],{time:2000n}));
  assert.equal(await f.read(asset,token,'balanceOf',[ALICE]),1007n);
  assert.equal(await f.read(lock,vesting,'released'),1000n);
});
