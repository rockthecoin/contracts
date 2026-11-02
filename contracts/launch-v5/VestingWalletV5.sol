// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VestingWalletV5 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable token; address public immutable beneficiary; uint256 public immutable allocation;
    uint64 public immutable start; uint64 public immutable cliff; uint64 public immutable end; uint256 public released;
    event Released(uint256 amount);
    constructor(address asset,address recipient,uint256 amount,uint64 begins,uint64 cliffAt,uint64 ends){
        require(asset!=address(0)&&recipient!=address(0)&&amount>0&&begins>0&&begins<=cliffAt&&cliffAt<=ends,"Invalid vesting");
        token=IERC20(asset);beneficiary=recipient;allocation=amount;start=begins;cliff=cliffAt;end=ends;
    }
    function vestedAmount(uint256 timestamp) public view returns(uint256){
        if(timestamp<cliff)return 0;if(timestamp>=end)return allocation;
        uint256 elapsed=timestamp-start;uint256 duration=end-start;
        return(allocation/duration)*elapsed+((allocation%duration)*elapsed)/duration;
    }
    function releasable() public view returns(uint256){uint256 accrued=vestedAmount(block.timestamp)-released;uint256 balance=token.balanceOf(address(this));return accrued<balance?accrued:balance;}
    function release() external nonReentrant {uint256 amount=releasable();require(amount>0,"Nothing vested");released+=amount;token.safeTransfer(beneficiary,amount);emit Released(amount);}
    function releaseSurplus() external nonReentrant {require(msg.sender==beneficiary,"Beneficiary only");uint256 balance=token.balanceOf(address(this));uint256 reserved=allocation-released;require(balance>reserved,"No surplus");token.safeTransfer(beneficiary,balance-reserved);}
}
contract PositionLockV5 is IERC721Receiver,ReentrancyGuard {
    IERC721 public immutable token;uint256 public immutable tokenId;address public immutable beneficiary;uint64 public immutable unlockAt;
    constructor(address asset,uint256 id,address recipient,uint64 unlock){require(asset!=address(0)&&recipient!=address(0)&&unlock>block.timestamp,"Invalid lock");token=IERC721(asset);tokenId=id;beneficiary=recipient;unlockAt=unlock;}
    function onERC721Received(address,address,uint256 id,bytes calldata) external view returns(bytes4){require(msg.sender==address(token)&&id==tokenId,"Wrong position");return IERC721Receiver.onERC721Received.selector;}
    function release() external nonReentrant {require(block.timestamp>=unlockAt,"Position locked");token.safeTransferFrom(address(this),beneficiary,tokenId);}
}
