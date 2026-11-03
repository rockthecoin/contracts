// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @dev ERC-2612 checks from OpenZeppelin 5.6.1, with a clone-specific domain.
/// No cached implementation address or implementation name is used for signing.
abstract contract TronClonePermit is ERC20,IERC20Permit,EIP712,Nonces {
    bytes32 private constant PERMIT_TYPEHASH=keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer,address owner);
    constructor() EIP712("","1") {}
    function _cloneDomain() internal view virtual returns(bytes32);
    function permit(address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s) public virtual {
        if(block.timestamp>deadline)revert ERC2612ExpiredSignature(deadline);
        bytes32 hash=_hashTypedDataV4(keccak256(abi.encode(PERMIT_TYPEHASH,owner,spender,value,_useNonce(owner),deadline)));
        address signer=ECDSA.recover(hash,v,r,s);
        if(signer!=owner)revert ERC2612InvalidSigner(signer,owner);
        _approve(owner,spender,value);
    }
    function nonces(address owner) public view virtual override(IERC20Permit,Nonces) returns(uint256){return super.nonces(owner);}
    function DOMAIN_SEPARATOR() external view returns(bytes32){return _cloneDomain();}
}
