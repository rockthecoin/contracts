// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
/// @notice Atomic native/token distribution and approved-protocol liquidity calls.
/// @dev Quotes authorize the full plan, caller, chain, contract and native fee.
/// Pre-existing contract balances cannot be spent, and temporary allowances are cleared.
contract ServiceTools is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct FeeQuote {uint256 fee;address treasury;bytes32 referenceId;uint256 expiresAt;uint256 feeEurCents;}
    struct TokenInput {address token;uint256 amount;}
    struct ProtocolCall {address target;uint256 value;bytes data;}
    struct PositionAuthorization {address manager;uint256 tokenId;}
    bytes32 private constant DOMAIN_TYPEHASH=keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant QUOTE_TYPEHASH=keccak256("OperationQuote(address creator,bytes32 operationHash,uint256 fee,address treasury,bytes32 referenceId,uint256 expiresAt,uint256 feeEurCents)");
    address public treasury;
    address public quoteSigner;
    bool public paused;
    mapping(bytes32=>bool) public usedReferences;
    mapping(address=>bool) public allowedTargets;
    event OperationCompleted(address indexed creator,bytes32 indexed referenceId,bytes32 indexed operationHash,uint256 fee,address treasury);
    event ConfigurationChanged(address treasury,address quoteSigner);
    event TargetChanged(address indexed target,bool allowed);
    event PauseChanged(bool paused);
    error InvalidPlan();error UnauthorizedQuote();error QuoteExpired();error DuplicateReference();error PaymentFailed();error BalanceViolation();error UnsupportedTransferTax();
    constructor(address initialOwner,address treasury_,address signer_) Ownable(initialOwner){_configuration(treasury_,signer_);}
    receive() external payable {}
    function _configuration(address treasury_,address signer_) private {if(treasury_==address(0)||signer_==address(0)||treasury_==address(this))revert InvalidPlan();treasury=treasury_;quoteSigner=signer_;emit ConfigurationChanged(treasury_,signer_);}
    function setConfiguration(address treasury_,address signer_) external onlyOwner {_configuration(treasury_,signer_);}
    function setPaused(bool value) external onlyOwner {paused=value;emit PauseChanged(value);}
    function setAllowedTarget(address target,bool allowed) external onlyOwner {if(target==address(0)||target==address(this)||target.code.length==0)revert InvalidPlan();allowedTargets[target]=allowed;emit TargetChanged(target,allowed);}
    function setAllowedTargets(address[] calldata targets,bool allowed) external onlyOwner {if(targets.length>12)revert InvalidPlan();for(uint256 i;i<targets.length;i++){address target=targets[i];if(target==address(0)||target==address(this)||target.code.length==0)revert InvalidPlan();allowedTargets[target]=allowed;emit TargetChanged(target,allowed);}}
    function quoteDigest(address creator,bytes32 operationHash,FeeQuote calldata q) public view returns(bytes32){
        bytes32 domain=keccak256(abi.encode(DOMAIN_TYPEHASH,keccak256("RockTheCoinTools"),keccak256("1"),block.chainid,address(this)));
        bytes32 body=keccak256(abi.encode(QUOTE_TYPEHASH,creator,operationHash,q.fee,q.treasury,q.referenceId,q.expiresAt,q.feeEurCents));return keccak256(abi.encodePacked("\x19\x01",domain,body));
    }
    function _authorize(bytes32 operationHash,FeeQuote calldata q,bytes calldata signature) private {
        if(paused||q.treasury!=treasury||q.referenceId==bytes32(0))revert InvalidPlan();
        if(block.timestamp>q.expiresAt||q.expiresAt>block.timestamp+300)revert QuoteExpired();
        if(usedReferences[q.referenceId])revert DuplicateReference();
        if(ECDSA.recover(quoteDigest(msg.sender,operationHash,q),signature)!=quoteSigner)revert UnauthorizedQuote();usedReferences[q.referenceId]=true;
    }
    function _pay(uint256 value,address to) private {if(value!=0){(bool ok,)=payable(to).call{value:value}("");if(!ok)revert PaymentFailed();}}
    function _finish(bytes32 operationHash,FeeQuote calldata q) private {_pay(q.fee,q.treasury);emit OperationCompleted(msg.sender,q.referenceId,operationHash,q.fee,q.treasury);}
    function _recipients(address[] calldata recipients,uint256[] calldata amounts) private pure returns(uint256 total){if(recipients.length==0||recipients.length>100||recipients.length!=amounts.length)revert InvalidPlan();for(uint256 i;i<recipients.length;i++){if(recipients[i]==address(0)||amounts[i]==0)revert InvalidPlan();total+=amounts[i];}}
    function sendNative(address[] calldata recipients,uint256[] calldata amounts,FeeQuote calldata q,bytes calldata signature) external payable nonReentrant {
        bytes32 operationHash=keccak256(abi.encode(uint8(0),recipients,amounts));_authorize(operationHash,q,signature);uint256 total=_recipients(recipients,amounts);if(msg.value!=total+q.fee)revert InvalidPlan();
        for(uint256 i;i<recipients.length;i++)_pay(amounts[i],recipients[i]);_finish(operationHash,q);
    }
    /// @notice Amounts are gross transfers; a taxed token may deliver less to recipients.
    function sendTokens(address token,address[] calldata recipients,uint256[] calldata amounts,FeeQuote calldata q,bytes calldata signature) external payable nonReentrant {
        bytes32 operationHash=keccak256(abi.encode(uint8(1),token,recipients,amounts));_authorize(operationHash,q,signature);_recipients(recipients,amounts);if(token.code.length==0||msg.value!=q.fee)revert InvalidPlan();
        for(uint256 i;i<recipients.length;i++)IERC20(token).safeTransferFrom(msg.sender,recipients[i],amounts[i]);_finish(operationHash,q);
    }
    function execute(TokenInput[] calldata inputs,ProtocolCall[] calldata calls,PositionAuthorization[] calldata positions,FeeQuote calldata q,bytes calldata signature) external payable nonReentrant {
        bytes32 operationHash=keccak256(abi.encode(uint8(2),inputs,calls,positions));_authorize(operationHash,q,signature);
        if(inputs.length>6||calls.length==0||calls.length>12||positions.length>4||msg.value<q.fee)revert InvalidPlan();uint256 nativeBaseline=address(this).balance-msg.value;
        uint256[] memory balances=new uint256[](inputs.length);
        for(uint256 i;i<positions.length;i++){if(!allowedTargets[positions[i].manager]||IERC721(positions[i].manager).ownerOf(positions[i].tokenId)!=msg.sender)revert InvalidPlan();}
        for(uint256 i;i<inputs.length;i++){
            if(inputs[i].token.code.length==0)revert InvalidPlan();for(uint256 j;j<i;j++)if(inputs[i].token==inputs[j].token)revert InvalidPlan();
            IERC20 token=IERC20(inputs[i].token);balances[i]=token.balanceOf(address(this));if(inputs[i].amount>0){token.safeTransferFrom(msg.sender,address(this),inputs[i].amount);if(token.balanceOf(address(this))!=balances[i]+inputs[i].amount)revert UnsupportedTransferTax();}
            for(uint256 j;j<calls.length;j++){if(!allowedTargets[calls[j].target]||calls[j].target==address(this))revert InvalidPlan();if(inputs[i].amount>0)token.forceApprove(calls[j].target,inputs[i].amount);}
        }
        uint256 callValue;for(uint256 i;i<calls.length;i++){if(!allowedTargets[calls[i].target])revert InvalidPlan();callValue+=calls[i].value;if(callValue>msg.value-q.fee)revert InvalidPlan();(bool ok,bytes memory result)=calls[i].target.call{value:calls[i].value}(calls[i].data);if(!ok){assembly("memory-safe"){revert(add(result,32),mload(result))}}}
        for(uint256 i;i<inputs.length;i++){
            IERC20 token=IERC20(inputs[i].token);for(uint256 j;j<calls.length;j++)if(inputs[i].amount>0)token.forceApprove(calls[j].target,0);
            uint256 balance=token.balanceOf(address(this));if(balance<balances[i])revert BalanceViolation();if(balance>balances[i])token.safeTransfer(msg.sender,balance-balances[i]);if(token.balanceOf(address(this))<balances[i])revert BalanceViolation();
        }
        if(address(this).balance<nativeBaseline+q.fee)revert BalanceViolation();_finish(operationHash,q);_pay(address(this).balance-nativeBaseline,msg.sender);
    }
}
