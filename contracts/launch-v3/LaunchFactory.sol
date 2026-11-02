// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ConfigurableToken,TokenConfiguration} from "./ConfigurableToken.sol";

/// @notice Versioned factory. Existing v2 factories and tokens remain independent.
contract LaunchFactory is Ownable2Step,ReentrancyGuard {
    struct Quote{uint256 fee;address treasury;bytes32 referenceId;uint256 expiresAt;uint256 feeEurCents;}
    bytes32 private constant DOMAIN=keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant QUOTE=keccak256("CreationQuote(address creator,uint8 kind,bytes32 assetHash,uint256 fee,address treasury,bytes32 referenceId,uint256 expiresAt,uint256 feeEurCents)");
    address payable public treasury;
    address public quoteSigner;
    bool public paused;
    mapping(bytes32=>bool) public usedReferences;
    mapping(address=>address) public creatorOf;
    event AssetCreated(address indexed creator,address indexed asset,bytes32 indexed referenceId,uint8 kind,uint256 fee,address treasury);
    event TokenConfigurationRecorded(address indexed asset,bytes32 indexed configurationHash);
    event ConfigurationChanged(address treasury,address quoteSigner);
    event PauseChanged(bool paused);
    error InvalidQuote();error PaymentRejected();error InvalidConfiguration();
    constructor(address initialOwner,address payable recipient,address signer) Ownable(initialOwner){_configure(recipient,signer);}
    function setConfiguration(address payable recipient,address signer) external onlyOwner{_configure(recipient,signer);}
    function _configure(address payable recipient,address signer) private {
        if(recipient==address(0)||signer==address(0))revert InvalidConfiguration();treasury=recipient;quoteSigner=signer;emit ConfigurationChanged(recipient,signer);
    }
    function setPaused(bool value) external onlyOwner{paused=value;emit PauseChanged(value);}
    function quoteDigest(address creator,bytes32 assetHash,Quote calldata q) public view returns(bytes32){
        bytes32 domain=keccak256(abi.encode(DOMAIN,keccak256("RockTheCoinLaunch"),keccak256("3"),block.chainid,address(this)));
        return keccak256(abi.encodePacked("\x19\x01",domain,keccak256(abi.encode(QUOTE,creator,uint8(0),assetHash,q.fee,q.treasury,q.referenceId,q.expiresAt,q.feeEurCents))));
    }
    function createToken(TokenConfiguration calldata configuration,Quote calldata q,bytes calldata signature) external payable nonReentrant returns(address asset){
        bytes32 assetHash=keccak256(abi.encode(configuration));
        if(paused||msg.value!=q.fee||q.treasury!=treasury||q.referenceId==bytes32(0)||usedReferences[q.referenceId]||
           q.expiresAt<block.timestamp||q.expiresAt>block.timestamp+300||ECDSA.recover(quoteDigest(msg.sender,assetHash,q),signature)!=quoteSigner)revert InvalidQuote();
        usedReferences[q.referenceId]=true;asset=address(new ConfigurableToken(configuration));creatorOf[asset]=msg.sender;
        if(q.fee!=0){(bool paid,)=treasury.call{value:q.fee}("");if(!paid)revert PaymentRejected();}
        emit AssetCreated(msg.sender,asset,q.referenceId,0,q.fee,treasury);emit TokenConfigurationRecorded(asset,assetHash);
    }
}
