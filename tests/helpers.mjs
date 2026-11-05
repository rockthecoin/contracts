import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createVM} from '@ethereumjs/vm';
import {Common,Mainnet,Hardfork} from '@ethereumjs/common';
import {createBlock} from '@ethereumjs/block';
import {Account,createAddressFromString,hexToBytes,bytesToHex} from '@ethereumjs/util';
import {encodeDeployData,encodeFunctionData,decodeFunctionResult,decodeEventLog,encodeAbiParameters,keccak256} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';

// Public deterministic fixture key. Never fund or use this key outside these tests.
export const signer=privateKeyToAccount('0x'+'01'.repeat(32));
export const OWNER='0x'+'11'.repeat(20),CREATOR='0x'+'22'.repeat(20),TREASURY='0x'+'33'.repeat(20),ALICE='0x'+'44'.repeat(20),BOB='0x'+'55'.repeat(20),ZERO='0x'+'00'.repeat(20);
export const artifact=path=>JSON.parse(fs.readFileSync(path,'utf8'));
export const hashArgs=(contract,method,args)=>keccak256(encodeAbiParameters(contract.abi.find(x=>x.name===method&&x.type==='function').inputs.slice(0,args.length),args));
export function expectSuccess(result){assert.equal(result.execResult.exceptionError,undefined,bytesToHex(result.execResult.returnValue));return result;}
export function expectRevert(result){assert.ok(result.execResult.exceptionError,'Expected EVM revert');}
export function event(result,contract,name){
  for(const [,topics,data] of result.execResult.logs??[]){try{const e=decodeEventLog({abi:contract.abi,topics:topics.map(bytesToHex),data:bytesToHex(data)});if(e.eventName===name)return e.args;}catch{}}
  assert.fail(`Missing ${name} event`);
}
export async function fixture(chainId=1){
  const common=new Common({chain:{...Mainnet,chainId},hardfork:chainId===10?Hardfork.Osaka:Hardfork.Cancun}),vm=await createVM({common});
  const address=createAddressFromString;
  for(const who of [OWNER,CREATOR,TREASURY,ALICE,BOB])await vm.stateManager.putAccount(address(who),new Account(0n,10n**24n));
  const block=time=>createBlock({header:{timestamp:time,gasLimit:chainId===10?40000000n:50000000n}},{common});
  async function deploy(contract,args=[]){
    const result=await vm.evm.runCall({caller:address(OWNER),origin:address(OWNER),data:hexToBytes(encodeDeployData({...contract,args})),gasLimit:chainId===10?16777216n:30000000n,block:block(1000n)});
    expectSuccess(result);return result.createdAddress.toString();
  }
  async function call(to,contract,method,args=[],{caller=CREATOR,value=0n,time=1000n}={}){
    return vm.evm.runCall({caller:address(caller),origin:address(caller),to:address(to),data:hexToBytes(encodeFunctionData({abi:contract.abi,functionName:method,args})),value,gasLimit:chainId===10?16777216n:30000000n,block:block(time)});
  }
  async function read(to,contract,method,args=[]){const r=expectSuccess(await call(to,contract,method,args));return decodeFunctionResult({abi:contract.abi,functionName:method,data:bytesToHex(r.execResult.returnValue)});}
  let serial=0;
  const quote=()=>({fee:1000n,treasury:TREASURY,referenceId:'0x'+(++serial).toString(16).padStart(64,'0'),expiresAt:1180n,feeEurCents:2000n});
  const balance=async who=>(await vm.stateManager.getAccount(address(who)))?.balance??0n;
  const putCode=(who,code)=>vm.stateManager.putCode(address(who),hexToBytes(code));
  return {vm,chainId,deploy,call,read,quote,balance,putCode};
}
const feeFields=[{name:'fee',type:'uint256'},{name:'treasury',type:'address'},{name:'referenceId',type:'bytes32'},{name:'expiresAt',type:'uint256'},{name:'feeEurCents',type:'uint256'}];
export async function authorize(f,contract,address,hash,q,{kind=0,domain='RockTheCoin',version='2',type='CreationQuote',chainId=f.chainId}={}){
  const primaryType=type;
  const fields=type==='CreationQuote'?[{name:'creator',type:'address'},{name:'kind',type:'uint8'},{name:'assetHash',type:'bytes32'},...feeFields]:[{name:'creator',type:'address'},{name:type==='CollectionQuote'?'configurationHash':'operationHash',type:'bytes32'},...feeFields];
  const message={creator:CREATOR,...q,...(type==='CreationQuote'?{kind,assetHash:hash}:type==='CollectionQuote'?{configurationHash:hash}:{operationHash:hash})};
  return signer.signTypedData({domain:{name:domain,version,chainId,verifyingContract:address},primaryType,types:{[primaryType]:fields},message});
}
export function configuration(changes={}){return {
  name:'Public contract test',symbol:'RTC',decimals:0,initialSupply:10000n,maximumSupply:10000n,administrator:ZERO,
  mintable:false,burnable:true,pausable:false,blocklist:false,permitEnabled:false,votingEnabled:false,lifetimeCap:false,
  transferTaxBps:0,buyTaxBps:0,sellTaxBps:0,maximumTaxBps:0,mutableTax:false,mutableRecipients:false,mutablePools:false,
  taxRecipients:[],taxShares:[],taxExemptions:[],pools:[],maximumTransaction:0n,maximumWallet:0n,cooldown:0,tradingStarts:0n,
  mutableLimits:false,mutableTrading:false,limitExemptions:[],roles:[],...changes
};}
