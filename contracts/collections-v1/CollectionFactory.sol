// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {NFTCollection} from "./NFTCollection.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract CollectionFactory is Ownable2Step, ReentrancyGuard {
    struct Configuration { string name; string symbol; string uri; uint256 maxSupply; address royaltyReceiver; uint96 royaltyBps; }
    struct Quote { uint256 fee; address treasury; bytes32 referenceId; uint256 expiresAt; uint256 feeEurCents; }
    address payable public treasury;
    address public quoteSigner;
    bool public paused;
    mapping(bytes32 => bool) public usedReferences;
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant QUOTE_TYPEHASH = keccak256("CollectionQuote(address creator,bytes32 configurationHash,uint256 fee,address treasury,bytes32 referenceId,uint256 expiresAt,uint256 feeEurCents)");
    event ConfigurationUpdated(address treasury, address quoteSigner);
    event PauseChanged(bool paused);
    event CollectionCreated(address indexed creator, address indexed collection, bytes32 indexed referenceId, uint256 fee, address treasury);
    error InvalidConfiguration();
    error InvalidQuote();
    error PaymentFailed();

    constructor(address owner_, address payable treasury_, address signer_) Ownable(owner_) { _configure(treasury_, signer_); }
    function setConfiguration(address payable treasury_, address signer_) external onlyOwner { _configure(treasury_, signer_); }
    function _configure(address payable treasury_, address signer_) private {
        if (treasury_ == address(0) || treasury_ == address(this) || signer_ == address(0)) revert InvalidConfiguration();
        treasury = treasury_; quoteSigner = signer_; emit ConfigurationUpdated(treasury_, signer_);
    }
    function setPaused(bool value) external onlyOwner { paused = value; emit PauseChanged(value); }
    function quoteDigest(address creator, bytes32 configurationHash, Quote calldata q) public view returns (bytes32) {
        bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("RockTheCoinCollections"), keccak256("1"), block.chainid, address(this)));
        return MessageHashUtils.toTypedDataHash(domain, keccak256(abi.encode(QUOTE_TYPEHASH, creator, configurationHash,
            q.fee, q.treasury, q.referenceId, q.expiresAt, q.feeEurCents)));
    }
    function createCollection(Configuration calldata c, Quote calldata q, bytes calldata signature)
        external payable nonReentrant returns (address collection)
    {
        if (paused || msg.value != q.fee || treasury != q.treasury || block.timestamp > q.expiresAt
            || q.expiresAt > block.timestamp + 5 minutes || q.referenceId == bytes32(0) || usedReferences[q.referenceId]
            || ECDSA.recover(quoteDigest(msg.sender, keccak256(abi.encode(c)), q), signature) != quoteSigner) revert InvalidQuote();
        usedReferences[q.referenceId] = true;
        collection = address(new NFTCollection(c.name, c.symbol, c.uri, c.maxSupply, c.royaltyReceiver, c.royaltyBps, msg.sender));
        (bool ok,) = treasury.call{value: msg.value}("");
        if (!ok) revert PaymentFailed();
        emit CollectionCreated(msg.sender, collection, q.referenceId, msg.value, treasury);
    }
}
