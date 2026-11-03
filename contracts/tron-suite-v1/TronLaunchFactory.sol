// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TronToken} from "./TronToken.sol";
import {TronTokenConfiguration,TronAllocation} from "./LaunchTypes.sol";
import {TronVestingWallet,TronPositionLock} from "./TronVestingWallet.sol";

/// @dev Creation code is stored in inert code blobs so no deployed contract exceeds EIP-170.
contract TronCodeStorage {
    constructor(bytes memory code){bytes memory data=abi.encodePacked(hex"00",code);assembly("memory-safe"){return(add(data,32),mload(data))}}
}
contract TronTokenDeployer {
    address public immutable factory;
    address public codePartA;address public codePartB;bytes32 public creationCodeHash;
    constructor(bytes memory code){
        factory=msg.sender;creationCodeHash=keccak256(code);uint256 cut=code.length>20000?20000:code.length;
        bytes memory first=new bytes(cut);bytes memory second=new bytes(code.length-cut);
        // Cancun MCOPY avoids a per-byte deployment loop and its TVM energy cost.
        assembly("memory-safe"){mcopy(add(first,32),add(code,32),cut)mcopy(add(second,32),add(add(code,32),cut),mload(second))}
        codePartA=address(new TronCodeStorage(first));codePartB=address(new TronCodeStorage(second));
    }
    function creationCode() public view returns(bytes memory code){
        address a=codePartA;address b=codePartB;uint256 left=a.code.length-1;uint256 right=b.code.length-1;code=new bytes(left+right);
        assembly("memory-safe"){extcodecopy(a,add(code,32),1,left)extcodecopy(b,add(add(code,32),left),1,right)}
    }
    function deploy(TronTokenConfiguration calldata config) external returns(TronToken token){
        require(msg.sender==factory,"Factory only");bytes memory code=abi.encodePacked(creationCode(),abi.encode(config,factory));address asset;
        assembly("memory-safe"){asset:=create(0,add(code,32),mload(code))}
        require(asset!=address(0),"Token deployment failed");token=TronToken(asset);
    }
}
contract TronLaunchFactory is Ownable2Step,ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct Quote{uint256 fee;address treasury;bytes32 referenceId;uint256 expiresAt;uint256 feeEurCents;}
    bytes32 private constant DOMAIN=keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant QUOTE=keccak256("CreationQuote(address creator,uint8 kind,bytes32 assetHash,uint256 fee,address treasury,bytes32 referenceId,uint256 expiresAt,uint256 feeEurCents)");
    address payable public treasury;address public quoteSigner;bool public paused;
    TronTokenDeployer public tokenDeployer;
    mapping(bytes32=>bool) public usedReferences;mapping(address=>address) public creatorOf;
    mapping(address=>address[]) public vestingWallets;
    event AssetCreated(address indexed creator,address indexed asset,bytes32 indexed referenceId,uint8 kind,uint256 fee,address treasury);
    event TokenConfigurationRecorded(address indexed asset,bytes32 indexed configurationHash);
    event AllocationCreated(address indexed token,uint256 indexed index,address indexed beneficiary,address vestingWallet,uint256 amount,uint64 start,uint64 cliff,uint64 end);
    event LockCreated(address indexed creator,address indexed lock,bytes32 indexed referenceId,address token,uint256 amountOrId,bool position);
    event ConfigurationChanged(address treasury,address quoteSigner);event PauseChanged(bool paused);
    error InvalidQuote();error PaymentRejected();error InvalidConfiguration();
    constructor(address initialOwner,address payable recipient,address signer) Ownable(initialOwner){_configure(recipient,signer);tokenDeployer=new TronTokenDeployer(type(TronToken).creationCode);}
    function setConfiguration(address payable recipient,address signer) external onlyOwner {_configure(recipient,signer);}
    function _configure(address payable recipient,address signer) private {if(recipient==address(0)||recipient==address(this)||signer==address(0))revert InvalidConfiguration();treasury=recipient;quoteSigner=signer;emit ConfigurationChanged(recipient,signer);}
    function setPaused(bool value) external onlyOwner {paused=value;emit PauseChanged(value);}
    function quoteDigest(address creator,uint8 kind,bytes32 assetHash,Quote calldata q) public view returns(bytes32){
        bytes32 domain=keccak256(abi.encode(DOMAIN,keccak256("RockTheCoinTRONLaunch"),keccak256("1"),block.chainid,address(this)));
        return keccak256(abi.encodePacked("\x19\x01",domain,keccak256(abi.encode(QUOTE,creator,kind,assetHash,q.fee,q.treasury,q.referenceId,q.expiresAt,q.feeEurCents))));
    }
    function _authorize(uint8 kind,bytes32 assetHash,Quote calldata q,bytes calldata signature) private {
        if(paused||msg.value!=q.fee||q.treasury!=treasury||q.referenceId==bytes32(0)||usedReferences[q.referenceId]||q.expiresAt<block.timestamp||
           q.expiresAt>block.timestamp+300||ECDSA.recover(quoteDigest(msg.sender,kind,assetHash,q),signature)!=quoteSigner)revert InvalidQuote();
        usedReferences[q.referenceId]=true;
    }
    function _pay(Quote calldata q) private {if(q.fee!=0){(bool paid,)=treasury.call{value:q.fee}("");if(!paid)revert PaymentRejected();}}
    function createToken(TronTokenConfiguration calldata config,TronAllocation[] calldata allocations,Quote calldata q,bytes calldata signature) external payable nonReentrant returns(address asset){
        bytes32 hash=keccak256(abi.encode(config,allocations));_authorize(0,hash,q,signature);
        if(allocations.length>50)revert InvalidConfiguration();uint256 total;
        for(uint256 i;i<allocations.length;i++){if(allocations[i].beneficiary==address(0)||allocations[i].amount==0)revert InvalidConfiguration();total+=allocations[i].amount;}
        if(total!=config.initialSupply)revert InvalidConfiguration();
        TronToken token=tokenDeployer.deploy(config);asset=address(token);creatorOf[asset]=msg.sender;
        for(uint256 i;i<allocations.length;i++){
            TronAllocation calldata a=allocations[i];address escrow;
            if(a.start!=0)escrow=address(new TronVestingWallet(asset,a.beneficiary,a.amount,a.start,a.cliff,a.end));
            else if(a.cliff!=0||a.end!=0)revert InvalidConfiguration();
            token.distributeInitial(escrow==address(0)?a.beneficiary:escrow,a.amount);vestingWallets[asset].push(escrow);
            emit AllocationCreated(asset,i,a.beneficiary,escrow,a.amount,a.start,a.cliff,a.end);
        }
        token.finishDistribution();_pay(q);emit AssetCreated(msg.sender,asset,q.referenceId,0,q.fee,treasury);emit TokenConfigurationRecorded(asset,hash);
    }
    function createVesting(address asset,address beneficiary,uint256 amount,uint64 start,uint64 cliff,uint64 end,Quote calldata q,bytes calldata signature) external payable nonReentrant returns(address lock){
        _authorize(1,keccak256(abi.encode(asset,beneficiary,amount,start,cliff,end)),q,signature);
        lock=address(new TronVestingWallet(asset,beneficiary,amount,start,cliff,end));
        // A predictable escrow may already hold donated tokens. Validate the deposit delta.
        uint256 beforeBalance=IERC20(asset).balanceOf(lock);IERC20(asset).safeTransferFrom(msg.sender,lock,amount);
        if(IERC20(asset).balanceOf(lock)!=beforeBalance+amount)revert InvalidConfiguration();_pay(q);emit LockCreated(msg.sender,lock,q.referenceId,asset,amount,false);
    }
    function lockPosition(address asset,uint256 id,address beneficiary,uint64 unlock,Quote calldata q,bytes calldata signature) external payable nonReentrant returns(address lock){
        _authorize(2,keccak256(abi.encode(asset,id,beneficiary,unlock)),q,signature);lock=address(new TronPositionLock(asset,id,beneficiary,unlock));
        IERC721(asset).safeTransferFrom(msg.sender,lock,id);_pay(q);emit LockCreated(msg.sender,lock,q.referenceId,asset,id,true);
    }
}
