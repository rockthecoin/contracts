// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;
// Constructor-only entry for unsigned mainnet TVM simulations. Never deploy.
import {TronServiceTools} from "contracts/tron-suite-v1/TronServiceTools.sol";
import {TronRewardsHook,SunPoolKey,SunSwapParams} from "contracts/tron-suite-v1/TronRewardsHook.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
interface ISunCLManager {
    function nextTokenId() external view returns(uint256);
    function initializePool(SunPoolKey calldata,uint160) external payable returns(int24);
    function modifyLiquidities(bytes calldata,uint256) external payable;
    function ownerOf(uint256) external view returns(address);
    function getPositionLiquidity(uint256) external view returns(uint128);
}
interface ISunPermit {function approve(address,address,uint160,uint48) external;function allowance(address,address,address)external view returns(uint160,uint48,uint48);}
interface ISunVault {
    function lock(bytes calldata) external returns(bytes memory);
    function swap(SunPoolKey calldata,SunSwapParams calldata,bytes calldata)external returns(int256);
    function currencyDelta(address,address)external view returns(int256);
    function sync(address)external;
    function settle()external payable returns(uint256);
    function take(address,address,uint256)external;
}
contract SunTestToken is ERC20 {constructor()ERC20("Unsigned SUN test","USUN"){_mint(msg.sender,1000000000000);}function decimals()public pure override returns(uint8){return 6;}}
contract SunV4Actor {
    TronServiceTools private tools;TronRewardsHook private rewards;SunTestToken private token;
    ISunCLManager private manager;ISunVault private vault;ISunPermit private permit;address private treasury;
    event SunV4Check(string action,uint256 position,uint256 value);
    constructor(address m,address v,address p){treasury=msg.sender;manager=ISunCLManager(m);vault=ISunVault(v);permit=ISunPermit(p);token=new SunTestToken();tools=new TronServiceTools(address(this),treasury,address(1));rewards=new TronRewardsHook(v,address(tools),address(this),address(1));}
    receive()external payable{}
    function onERC721Received(address,address,uint256,bytes calldata)external pure returns(bytes4){return this.onERC721Received.selector;}
    function run(bool withRewards,bytes calldata sig)external payable{
        SunPoolKey memory key=SunPoolKey(address(0),address(token),withRewards?address(rewards):address(0),3000,bytes32((uint256(60)<<16)|(withRewards?2177:0)));
        tools.setAllowedTarget(address(manager),true);tools.setAllowedTarget(address(permit),true);if(withRewards)tools.setAllowedTarget(address(rewards),true);
        TronServiceTools.TokenInput[] memory inputs=new TronServiceTools.TokenInput[](1);inputs[0]=TronServiceTools.TokenInput(address(token),100000);
        TronServiceTools.ProtocolCall[] memory calls=new TronServiceTools.ProtocolCall[](withRewards?5:4);uint256 i;
        calls[i++]=TronServiceTools.ProtocolCall(address(permit),0,abi.encodeCall(permit.approve,(address(token),address(manager),100000,uint48(block.timestamp+180))));
        if(withRewards){
            TronRewardsHook.Registration memory registration=TronRewardsHook.Registration(keccak256(abi.encode(key)),address(this),address(this),50,100,true,true,block.timestamp+180,keccak256("registration"));
            rewards.setQuoteSigner(ECDSA.recover(rewards.registrationDigest(registration),sig));calls[i++]=TronServiceTools.ProtocolCall(address(rewards),0,abi.encodeCall(rewards.registerPool,(key,registration,sig)));
        }
        calls[i++]=TronServiceTools.ProtocolCall(address(manager),0,abi.encodeCall(manager.initializePool,(key,uint160(1)<<96)));
        bytes[] memory params=new bytes[](3);params[0]=abi.encode(key,int24(-600),int24(600),uint256(1000000),uint128(100000),uint128(100000),address(this),bytes(""));params[1]=abi.encode(key.currency0,key.currency1);params[2]=abi.encode(address(0),address(tools));
        calls[i++]=TronServiceTools.ProtocolCall(address(manager),100000,abi.encodeCall(manager.modifyLiquidities,(abi.encode(hex"020d14",params),block.timestamp+180)));
        calls[i++]=TronServiceTools.ProtocolCall(address(permit),0,abi.encodeCall(permit.approve,(address(token),address(manager),0,0)));
        TronServiceTools.PositionAuthorization[] memory positions=new TronServiceTools.PositionAuthorization[](0);
        TronServiceTools.FeeQuote memory q=TronServiceTools.FeeQuote(1000,treasury,keccak256("mint"),block.timestamp+180,1000);
        tools.setConfiguration(treasury,ECDSA.recover(tools.quoteDigest(address(this),keccak256(abi.encode(uint8(2),inputs,calls,positions)),q),sig));token.approve(address(tools),100000);
        uint256 id=manager.nextTokenId();tools.execute{value:101000}(inputs,calls,positions,q,sig);require(manager.ownerOf(id)==address(this)&&manager.getPositionLiquidity(id)==1000000,"mint recipient/liquidity");
        (uint160 remaining,,)=permit.allowance(address(tools),address(token),address(manager));require(remaining==0&&token.balanceOf(address(tools))==0&&address(tools).balance==0&&token.allowance(address(tools),address(permit))==0,"helper cleanup");emit SunV4Check("mint/refund/revoke",id,1000000);
        token.approve(address(permit),100000);permit.approve(address(token),address(manager),100000,uint48(block.timestamp+180));params[0]=abi.encode(id,uint256(1000000),uint128(100000),uint128(100000),bytes(""));params[2]=abi.encode(address(0),address(this));manager.modifyLiquidities{value:100000}(abi.encode(hex"000d14",params),block.timestamp+180);permit.approve(address(token),address(manager),0,0);token.approve(address(permit),0);require(manager.getPositionLiquidity(id)==2000000,"owner increase");emit SunV4Check("owner increase",id,2000000);
        if(withRewards){
            vault.lock(abi.encode(key,true));vault.lock(abi.encode(key,false));uint256 a=rewards.claimable(address(this),address(0));uint256 b=rewards.claimable(address(this),address(token));require(a>0&&b>0,"native/token creator accrual");
            rewards.claim(address(0),address(this));rewards.claim(address(token),address(this));require(rewards.claimable(address(this),address(0))==0&&rewards.claimable(address(this),address(token))==0,"creator claim");rewards.configurePool(keccak256(abi.encode(key)),address(this),100,true,true);emit SunV4Check("creator swaps/claims/configuration",id,a+b);
        }
        bytes[] memory take=new bytes[](2);take[0]=abi.encode(id,uint256(0),uint128(0),uint128(0),bytes(""));take[1]=abi.encode(key.currency0,key.currency1);manager.modifyLiquidities(abi.encode(hex"0111",take),block.timestamp+180);emit SunV4Check("owner fee collection",id,0);
        take[0]=abi.encode(id,uint256(1000000),uint128(0),uint128(0),bytes(""));manager.modifyLiquidities(abi.encode(hex"0111",take),block.timestamp+180);require(manager.getPositionLiquidity(id)==1000000&&manager.ownerOf(id)==address(this),"owner withdrawal");emit SunV4Check("owner withdrawal",id,1000000);
    }
    function lockAcquired(bytes calldata data)external returns(bytes memory){
        require(msg.sender==address(vault),"vault");(SunPoolKey memory key,bool zeroForOne)=abi.decode(data,(SunPoolKey,bool));vault.swap(key,SunSwapParams(zeroForOne,-10000,zeroForOne?uint160(4295128740):uint160(1461446703485210103287273052203988822378723970341)),"");
        for(uint256 i;i<2;i++){address c=i==0?key.currency0:key.currency1;int256 delta=vault.currencyDelta(address(this),c);if(delta<0){vault.sync(c);if(c==address(0))vault.settle{value:uint256(-delta)}();else{require(token.transfer(address(vault),uint256(-delta)));vault.settle();}}else if(delta>0)vault.take(c,address(this),uint256(delta));}return "";
    }
}
contract TronSunV4Check {
    event SimulationPassed(bool rewards);
    constructor(bool rewards,bytes memory sig,address manager,address vault,address permit)payable{SunV4Actor actor=new SunV4Actor(manager,vault,permit);actor.run{value:msg.value}(rewards,sig);emit SimulationPassed(rewards);}
    receive()external payable{}
}
