// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId,PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency,CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta,BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Optional, disclosed creator rewards on separately registered Uniswap v4 pools.
/// @dev No transfer tax on the token itself. Exact-input swaps pay in output currency;
/// exact-output swaps pay in input currency. Pool rewards are capped permanently.
contract CreatorRewardsHook is Ownable2Step,ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;
    struct PoolConfig {address creator;address recipient;uint16 feeBps;uint16 maximumFeeBps;bool feeMutable;bool recipientMutable;address pendingCreator;}
    struct Registration {bytes32 poolId;address creator;address recipient;uint16 feeBps;uint16 maximumFeeBps;bool feeMutable;bool recipientMutable;uint256 expiresAt;bytes32 referenceId;}
    IPoolManager public immutable poolManager;
    address public immutable serviceTools;
    address public quoteSigner;
    bool public rewardsPaused;
    mapping(bytes32=>PoolConfig) public poolConfigs;
    mapping(bytes32=>bool) public registeredPools;
    mapping(bytes32=>bool) public usedReferences;
    mapping(address=>mapping(address=>uint256)) public claimable;
    bytes32 private constant DOMAIN_TYPEHASH=keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant REGISTRATION_TYPEHASH=keccak256("Registration(bytes32 poolId,address creator,address recipient,uint16 feeBps,uint16 maximumFeeBps,bool feeMutable,bool recipientMutable,uint256 expiresAt,bytes32 referenceId)");
    event PoolRegistered(bytes32 indexed poolId,address indexed creator,address recipient,uint16 feeBps,uint16 maximumFeeBps,bool feeMutable,bool recipientMutable);
    event PoolConfigurationChanged(bytes32 indexed poolId,address recipient,uint16 feeBps,bool feeMutable,bool recipientMutable);
    event PoolCreatorTransferStarted(bytes32 indexed poolId,address creator,address pendingCreator);
    event PoolCreatorChanged(bytes32 indexed poolId,address creator);
    event RewardAccrued(bytes32 indexed poolId,address indexed recipient,address indexed currency,uint256 amount);
    event RewardsClaimed(address indexed recipient,address indexed currency,address to,uint256 amount);
    event RewardsPauseChanged(bool paused);
    event QuoteSignerChanged(address signer);
    error InvalidConfiguration();error Unauthorized();error QuoteExpired();error AlreadyRegistered();error NoRewards();error UnsupportedRewardCurrency();
    constructor(address manager,address tools,address initialOwner,address signer) Ownable(initialOwner){
        // BEFORE_INITIALIZE | AFTER_SWAP | AFTER_SWAP_RETURNS_DELTA, and no other flags.
        if((uint160(address(this))&16383)!=8260||manager.code.length==0||tools.code.length==0||signer==address(0))revert InvalidConfiguration();
        poolManager=IPoolManager(manager);serviceTools=tools;quoteSigner=signer;
    }
    receive() external payable {if(msg.sender!=address(poolManager))revert Unauthorized();}
    function setQuoteSigner(address signer) external onlyOwner {if(signer==address(0))revert InvalidConfiguration();quoteSigner=signer;emit QuoteSignerChanged(signer);}
    /// @notice Pauses reward accrual and new registrations. Swaps and existing claims remain available.
    function setRewardsPaused(bool value) external onlyOwner {rewardsPaused=value;emit RewardsPauseChanged(value);}
    function registrationDigest(Registration calldata r) public view returns(bytes32){
        bytes32 domain=keccak256(abi.encode(DOMAIN_TYPEHASH,keccak256("RockTheCoinRewards"),keccak256("1"),block.chainid,address(this)));
        return keccak256(abi.encodePacked("\x19\x01",domain,keccak256(abi.encode(REGISTRATION_TYPEHASH,r.poolId,r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable,r.expiresAt,r.referenceId))));
    }
    function registerPool(PoolKey calldata key,Registration calldata r,bytes calldata signature) external {
        if(msg.sender!=serviceTools||rewardsPaused)revert Unauthorized();
        if(address(key.hooks)!=address(this)||PoolId.unwrap(key.toId())!=r.poolId||r.creator==address(0)||r.recipient==address(0)||r.recipient==address(this)||r.maximumFeeBps>1000||r.feeBps>r.maximumFeeBps||r.referenceId==bytes32(0))revert InvalidConfiguration();
        if(block.timestamp>r.expiresAt||r.expiresAt>block.timestamp+300)revert QuoteExpired();
        if(registeredPools[r.poolId]||usedReferences[r.referenceId])revert AlreadyRegistered();
        if(ECDSA.recover(registrationDigest(r),signature)!=quoteSigner)revert Unauthorized();
        registeredPools[r.poolId]=true;usedReferences[r.referenceId]=true;poolConfigs[r.poolId]=PoolConfig(r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable,address(0));
        emit PoolRegistered(r.poolId,r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable);
    }
    function beforeInitialize(address,PoolKey calldata key,uint160) external view returns(bytes4){if(msg.sender!=address(poolManager)||!registeredPools[PoolId.unwrap(key.toId())])revert Unauthorized();return this.beforeInitialize.selector;}
    function afterSwap(address,PoolKey calldata key,SwapParams calldata params,BalanceDelta delta,bytes calldata) external nonReentrant returns(bytes4,int128){
        if(msg.sender!=address(poolManager))revert Unauthorized();bytes32 id=PoolId.unwrap(key.toId());PoolConfig storage config=poolConfigs[id];if(rewardsPaused||config.feeBps==0)return(this.afterSwap.selector,0);
        bool currencyOne=params.zeroForOne==(params.amountSpecified<0);int256 amount=currencyOne?int256(delta.amount1()):int256(delta.amount0());uint256 absolute=uint256(amount<0?-amount:amount);uint256 fee=absolute*config.feeBps/10000;
        if(fee==0)return(this.afterSwap.selector,0);Currency currency=currencyOne?key.currency1:key.currency0;address token=Currency.unwrap(currency);address recipient=config.recipient;
        // A token can enable a transfer tax after pool creation. Never create an unbacked claim.
        uint256 beforeBalance=currency.balanceOfSelf();poolManager.take(currency,address(this),fee);
        if(currency.balanceOfSelf()!=beforeBalance+fee)revert UnsupportedRewardCurrency();
        claimable[recipient][token]+=fee;emit RewardAccrued(id,recipient,token,fee);return(this.afterSwap.selector,int128(int256(fee)));
    }
    function configurePool(bytes32 id,address recipient,uint16 feeBps,bool freezeFee,bool freezeRecipient) external {
        PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();
        if(recipient==address(0)||recipient==address(this)||feeBps>config.maximumFeeBps||(feeBps!=config.feeBps&&!config.feeMutable)||(recipient!=config.recipient&&!config.recipientMutable))revert InvalidConfiguration();
        config.feeBps=feeBps;config.recipient=recipient;if(freezeFee)config.feeMutable=false;if(freezeRecipient)config.recipientMutable=false;emit PoolConfigurationChanged(id,recipient,feeBps,config.feeMutable,config.recipientMutable);
    }
    function transferPoolCreator(bytes32 id,address next) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();if(next==address(0))revert InvalidConfiguration();config.pendingCreator=next;emit PoolCreatorTransferStarted(id,msg.sender,next);}
    function acceptPoolCreator(bytes32 id) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.pendingCreator)revert Unauthorized();config.creator=msg.sender;config.pendingCreator=address(0);emit PoolCreatorChanged(id,msg.sender);}
    function renouncePoolCreator(bytes32 id) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();if(config.feeMutable||config.recipientMutable||config.pendingCreator!=address(0))revert InvalidConfiguration();config.creator=address(0);emit PoolCreatorChanged(id,address(0));}
    function claim(address currency,address to) external nonReentrant {if(to==address(0)||to==address(this))revert InvalidConfiguration();uint256 value=claimable[msg.sender][currency];if(value==0)revert NoRewards();claimable[msg.sender][currency]=0;Currency.wrap(currency).transfer(to,value);emit RewardsClaimed(msg.sender,currency,to,value);}
}
