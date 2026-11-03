// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// SUN V4 uses a registration bitmap in PoolKey.parameters, not address flag bits.
// These ABI types match sun-protocol/sunswap-v4-core commit
// f57eece3d449d678fa078f497a1dd58f57bb60fe (MIT interfaces).
struct SunPoolKey { address currency0; address currency1; address hooks; uint24 fee; bytes32 parameters; }
struct SunSwapParams { bool zeroForOne; int256 amountSpecified; uint160 sqrtPriceLimitX96; }
interface ISunPoolManager { function take(address currency,address to,uint256 amount) external; }

/// @notice Optional capped creator rewards for separately registered SunSwap V4 pools.
/// @dev Exact-input rewards use output currency; exact-output rewards use input currency.
contract TronRewardsHook is Ownable2Step,ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct PoolConfig {address creator;address recipient;uint16 feeBps;uint16 maximumFeeBps;bool feeMutable;bool recipientMutable;address pendingCreator;}
    struct Registration {bytes32 poolId;address creator;address recipient;uint16 feeBps;uint16 maximumFeeBps;bool feeMutable;bool recipientMutable;uint256 expiresAt;bytes32 referenceId;}
    uint16 public constant HOOK_BITMAP=2177; // beforeInitialize | afterSwap | afterSwapReturnsDelta
    ISunPoolManager public immutable poolManager;
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
        if(manager.code.length==0||tools.code.length==0||signer==address(0))revert InvalidConfiguration();
        poolManager=ISunPoolManager(manager);serviceTools=tools;quoteSigner=signer;
    }
    receive() external payable {if(msg.sender!=address(poolManager))revert Unauthorized();}
    function getHooksRegistrationBitmap() external pure returns(uint16){return HOOK_BITMAP;}
    function setQuoteSigner(address signer) external onlyOwner {if(signer==address(0))revert InvalidConfiguration();quoteSigner=signer;emit QuoteSignerChanged(signer);}
    /// @notice Pauses new registration/accrual, preserving swaps and existing claims.
    function setRewardsPaused(bool value) external onlyOwner {rewardsPaused=value;emit RewardsPauseChanged(value);}
    function poolId(SunPoolKey calldata key) public pure returns(bytes32){return keccak256(abi.encode(key));}
    function registrationDigest(Registration calldata r) public view returns(bytes32){
        bytes32 domain=keccak256(abi.encode(DOMAIN_TYPEHASH,keccak256("RockTheCoinTRONRewards"),keccak256("1"),block.chainid,address(this)));
        return keccak256(abi.encodePacked("\x19\x01",domain,keccak256(abi.encode(REGISTRATION_TYPEHASH,r.poolId,r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable,r.expiresAt,r.referenceId))));
    }
    function registerPool(SunPoolKey calldata key,Registration calldata r,bytes calldata signature) external {
        if(msg.sender!=serviceTools||rewardsPaused)revert Unauthorized();
        if(key.hooks!=address(this)||uint16(uint256(key.parameters))!=HOOK_BITMAP||key.currency0>=key.currency1||poolId(key)!=r.poolId||r.creator==address(0)||r.recipient==address(0)||r.recipient==address(this)||r.maximumFeeBps>1000||r.feeBps>r.maximumFeeBps||r.referenceId==bytes32(0))revert InvalidConfiguration();
        if(block.timestamp>r.expiresAt||r.expiresAt>block.timestamp+300)revert QuoteExpired();
        if(registeredPools[r.poolId]||usedReferences[r.referenceId])revert AlreadyRegistered();
        if(ECDSA.recover(registrationDigest(r),signature)!=quoteSigner)revert Unauthorized();
        registeredPools[r.poolId]=true;usedReferences[r.referenceId]=true;
        poolConfigs[r.poolId]=PoolConfig(r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable,address(0));
        emit PoolRegistered(r.poolId,r.creator,r.recipient,r.feeBps,r.maximumFeeBps,r.feeMutable,r.recipientMutable);
    }
    function beforeInitialize(address,SunPoolKey calldata key,uint160) external view returns(bytes4){
        if(msg.sender!=address(poolManager)||!registeredPools[poolId(key)])revert Unauthorized();return this.beforeInitialize.selector;
    }
    function _balance(address currency) private view returns(uint256){return currency==address(0)?address(this).balance:IERC20(currency).balanceOf(address(this));}
    function afterSwap(address,SunPoolKey calldata key,SunSwapParams calldata params,int256 delta,bytes calldata) external nonReentrant returns(bytes4,int128){
        if(msg.sender!=address(poolManager))revert Unauthorized();bytes32 id=poolId(key);PoolConfig storage config=poolConfigs[id];
        if(rewardsPaused||config.feeBps==0)return(this.afterSwap.selector,0);
        bool currencyOne=params.zeroForOne==(params.amountSpecified<0);
        int256 amount=currencyOne?int256(int128(uint128(uint256(delta)))):int256(int128(delta>>128));
        uint256 absolute=uint256(amount<0?-amount:amount);uint256 fee=absolute*config.feeBps/10000;
        if(fee==0)return(this.afterSwap.selector,0);address currency=currencyOne?key.currency1:key.currency0;address recipient=config.recipient;
        uint256 beforeBalance=_balance(currency);poolManager.take(currency,address(this),fee);
        if(_balance(currency)!=beforeBalance+fee)revert UnsupportedRewardCurrency();
        claimable[recipient][currency]+=fee;emit RewardAccrued(id,recipient,currency,fee);return(this.afterSwap.selector,int128(int256(fee)));
    }
    function configurePool(bytes32 id,address recipient,uint16 feeBps,bool freezeFee,bool freezeRecipient) external {
        PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();
        if(recipient==address(0)||recipient==address(this)||feeBps>config.maximumFeeBps||(feeBps!=config.feeBps&&!config.feeMutable)||(recipient!=config.recipient&&!config.recipientMutable))revert InvalidConfiguration();
        config.feeBps=feeBps;config.recipient=recipient;if(freezeFee)config.feeMutable=false;if(freezeRecipient)config.recipientMutable=false;
        emit PoolConfigurationChanged(id,recipient,feeBps,config.feeMutable,config.recipientMutable);
    }
    function transferPoolCreator(bytes32 id,address next) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();if(next==address(0))revert InvalidConfiguration();config.pendingCreator=next;emit PoolCreatorTransferStarted(id,msg.sender,next);}
    function acceptPoolCreator(bytes32 id) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.pendingCreator)revert Unauthorized();config.creator=msg.sender;config.pendingCreator=address(0);emit PoolCreatorChanged(id,msg.sender);}
    function renouncePoolCreator(bytes32 id) external {PoolConfig storage config=poolConfigs[id];if(msg.sender!=config.creator)revert Unauthorized();if(config.feeMutable||config.recipientMutable||config.pendingCreator!=address(0))revert InvalidConfiguration();config.creator=address(0);emit PoolCreatorChanged(id,address(0));}
    function claim(address currency,address to) external nonReentrant {
        if(to==address(0)||to==address(this))revert InvalidConfiguration();uint256 value=claimable[msg.sender][currency];if(value==0)revert NoRewards();
        uint256 beforeBalance;if(currency!=address(0)){beforeBalance=_balance(currency);if(beforeBalance<value)revert UnsupportedRewardCurrency();}
        claimable[msg.sender][currency]=0;
        if(currency==address(0)){(bool ok,)=payable(to).call{value:value}("");if(!ok)revert UnsupportedRewardCurrency();}
        else {IERC20(currency).safeTransfer(to,value);if(_balance(currency)<beforeBalance-value)revert UnsupportedRewardCurrency();}
        emit RewardsClaimed(msg.sender,currency,to,value);
    }
}
