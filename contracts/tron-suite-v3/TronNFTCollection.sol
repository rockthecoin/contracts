// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Utils} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Utils.sol";

/// @notice Creator-owned ERC-721 collection. No platform fees on minting or transfers.
contract TronNFTCollection is ERC721URIStorage, ERC2981, Ownable2Step, ReentrancyGuard {
    address public immutable initializer;
    bool public initialized;
    string private collectionName;
    string private collectionSymbol;
    string public contractURI;
    uint256 public maxSupply;
    uint256 public mintedCount;
    bool public mintingClosed;
    mapping(bytes32 => bool) public usedMintReferences;

    event ItemsMinted(bytes32 indexed referenceId, uint256 firstTokenId, uint256 count);
    event MintingClosed();
    error InvalidCollection();
    error InvalidBatch();

    constructor() ERC721("", "") Ownable(msg.sender) { initializer = msg.sender; initialized = true; }
    function name() public view override returns (string memory) { return collectionName; }
    function symbol() public view override returns (string memory) { return collectionSymbol; }
    function initialize(string calldata name_, string calldata symbol_, string calldata uri_, uint256 cap_,
        address royaltyReceiver_, uint96 royaltyBps_, address creator_) external
    {
        if (initialized || msg.sender != initializer || creator_ == address(0)) revert InvalidCollection();
        initialized = true; StorageSlot.getUint256Slot(_reentrancyGuardStorageSlot()).value = 1; collectionName = name_; collectionSymbol = symbol_; _transferOwnership(creator_);
        if (bytes(name_).length == 0 || bytes(name_).length > 32 || bytes(symbol_).length == 0
            || bytes(symbol_).length > 10 || bytes(uri_).length == 0 || bytes(uri_).length > 500
            || cap_ == 0 || cap_ > 1000000 || royaltyReceiver_ == address(0) || royaltyBps_ > 10000) revert InvalidCollection();
        contractURI = uri_;
        maxSupply = cap_;
        if (royaltyBps_ != 0) _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
    }

    /// @dev Count is lifetime issuance: burning never restores minting capacity.
    function mintBatch(address[] calldata recipients, string[] calldata uris, bytes32 referenceId)
        external onlyOwner nonReentrant
    {
        uint256 count = recipients.length;
        if (mintingClosed || count == 0 || count > 20 || uris.length != count
            || mintedCount + count > maxSupply || referenceId == bytes32(0)
            || usedMintReferences[referenceId]) revert InvalidBatch();
        usedMintReferences[referenceId] = true;
        uint256 first = mintedCount + 1;
        mintedCount += count;
        for (uint256 i; i < count; ++i) {
            if (recipients[i] == address(0) || bytes(uris[i]).length == 0 || bytes(uris[i]).length > 500) revert InvalidBatch();
            // Store metadata before the recipient hook can inspect the new token.
            _mint(recipients[i], first + i);
            _setTokenURI(first + i, uris[i]);
            ERC721Utils.checkOnERC721Received(msg.sender, address(0), recipients[i], first + i, "");
        }
        emit ItemsMinted(referenceId, first, count);
    }

    function closeMinting() external onlyOwner { mintingClosed = true; emit MintingClosed(); }
    function burn(uint256 tokenId) external {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert ERC721InsufficientApproval(msg.sender, tokenId);
        _burn(tokenId);
    }
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
