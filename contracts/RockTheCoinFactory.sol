// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice A fixed-supply ERC20. No further minting, taxes, blacklist, or freeze controls.
contract RockToken is ERC20Burnable {
    uint8 private immutable tokenDecimals;
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 supply_, address creator_)
        ERC20(name_, symbol_)
    {
        tokenDecimals = decimals_;
        _mint(creator_, supply_);
    }
    function decimals() public view override returns (uint8) { return tokenDecimals; }
}

/// @notice One ERC721 asset in a new collection, owned by its creator.
contract RockNFT is ERC721URIStorage {
    constructor(string memory name_, string memory symbol_, string memory uri_, address creator_)
        ERC721(name_, symbol_)
    {
        _safeMint(creator_, 1);
        _setTokenURI(1, uri_);
    }
    function burn(uint256 tokenId) external {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert ERC721InsufficientApproval(msg.sender, tokenId);
        _burn(tokenId);
    }
}

/// @notice Asset creation and native-currency service payment are atomic.
/// @dev EUR pricing is converted off chain and authorized by a dedicated, unfunded quote signer.
contract RockTheCoinFactory is Ownable2Step, ReentrancyGuard {
    struct Quote {
        uint256 fee;
        address treasury;
        bytes32 referenceId;
        uint256 expiresAt;
        uint256 feeEurCents;
    }

    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("RockTheCoin");
    bytes32 private constant VERSION_HASH = keccak256("2");
    bytes32 private constant QUOTE_TYPEHASH = keccak256("CreationQuote(address creator,uint8 kind,bytes32 assetHash,uint256 fee,address treasury,bytes32 referenceId,uint256 expiresAt,uint256 feeEurCents)");

    address payable public treasury;
    address public quoteSigner;
    bool public paused;
    mapping(bytes32 => bool) public usedReferences;

    error WrongFee();
    error StaleTreasury();
    error CreationPaused();
    error InvalidAsset();
    error InvalidTreasury();
    error DuplicateReference();
    error PaymentFailed();
    error InvalidQuote();
    error QuoteExpired();

    event ConfigurationUpdated(address treasury, address quoteSigner);
    event PauseChanged(bool paused);
    event AssetCreated(address indexed creator, address indexed asset, bytes32 indexed referenceId,
        uint8 kind, uint256 fee, address treasury);

    constructor(address initialOwner, address payable initialTreasury, address initialQuoteSigner)
        Ownable(initialOwner)
    {
        _configure(initialTreasury, initialQuoteSigner);
    }

    function setConfiguration(address payable newTreasury, address newQuoteSigner) external onlyOwner {
        _configure(newTreasury, newQuoteSigner);
    }

    function _configure(address payable newTreasury, address newQuoteSigner) private {
        if (newTreasury == address(0) || newTreasury == address(this)) revert InvalidTreasury();
        if (newQuoteSigner == address(0)) revert InvalidQuote();
        treasury = newTreasury;
        quoteSigner = newQuoteSigner;
        emit ConfigurationUpdated(newTreasury, newQuoteSigner);
    }

    function setPaused(bool value) external onlyOwner { paused = value; emit PauseChanged(value); }

    function createToken(string calldata name_, string calldata symbol_, uint8 decimals_, uint256 supply_,
        Quote calldata quote, bytes calldata signature) external payable nonReentrant returns (address asset)
    {
        _check(0, keccak256(abi.encode(name_, symbol_, decimals_, supply_)), quote, signature);
        if (bytes(name_).length == 0 || bytes(name_).length > 32 || bytes(symbol_).length == 0
            || bytes(symbol_).length > 10 || decimals_ > 18 || supply_ == 0) revert InvalidAsset();
        asset = address(new RockToken(name_, symbol_, decimals_, supply_, msg.sender));
        _pay(asset, quote.referenceId, 0);
    }

    function createNFT(string calldata name_, string calldata symbol_, string calldata uri_,
        Quote calldata quote, bytes calldata signature) external payable nonReentrant returns (address asset)
    {
        _check(1, keccak256(abi.encode(name_, symbol_, uri_)), quote, signature);
        if (bytes(name_).length == 0 || bytes(name_).length > 32 || bytes(symbol_).length == 0
            || bytes(symbol_).length > 10 || bytes(uri_).length == 0 || bytes(uri_).length > 200) revert InvalidAsset();
        asset = address(new RockNFT(name_, symbol_, uri_, msg.sender));
        _pay(asset, quote.referenceId, 1);
    }

    function quoteDigest(address creator, uint8 kind, bytes32 assetHash, Quote calldata quote) public view returns (bytes32) {
        bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
        bytes32 message = keccak256(abi.encode(QUOTE_TYPEHASH, creator, kind, assetHash, quote.fee, quote.treasury,
            quote.referenceId, quote.expiresAt, quote.feeEurCents));
        return MessageHashUtils.toTypedDataHash(domain, message);
    }

    function _check(uint8 kind, bytes32 assetHash, Quote calldata quote, bytes calldata signature) private {
        if (paused) revert CreationPaused();
        if (msg.value != quote.fee) revert WrongFee();
        if (treasury != quote.treasury) revert StaleTreasury();
        if (block.timestamp > quote.expiresAt) revert QuoteExpired();
        if (quote.expiresAt > block.timestamp + 5 minutes) revert InvalidQuote();
        if (quote.referenceId == bytes32(0) || usedReferences[quote.referenceId]) revert DuplicateReference();
        if (ECDSA.recover(quoteDigest(msg.sender, kind, assetHash, quote), signature) != quoteSigner) revert InvalidQuote();
        usedReferences[quote.referenceId] = true;
    }

    function _pay(address asset, bytes32 referenceId, uint8 kind) private {
        address payable recipient = treasury;
        (bool success,) = recipient.call{value: msg.value}("");
        if (!success) revert PaymentFailed();
        emit AssetCreated(msg.sender, asset, referenceId, kind, msg.value, recipient);
    }
}
