// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TronVestingWallet is ReentrancyGuard {
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
    function release() external nonReentrant {uint256 amount=releasable();require(amount>0,"Nothing vested");released+=amount;_send(amount);emit Released(amount);}
    function releaseSurplus() external nonReentrant {require(msg.sender==beneficiary,"Beneficiary only");uint256 balance=token.balanceOf(address(this));uint256 reserved=allocation-released;require(balance>reserved,"No surplus");_send(balance-reserved);}
    // Sender surcharges must not consume unreleased principal or donated surplus.
    // Recipient-side transfer taxes remain gross payouts, as in the original API.
    function _send(uint256 amount) private {
        uint256 beforeBalance=token.balanceOf(address(this));
        token.safeTransfer(beneficiary,amount);
        require(token.balanceOf(address(this))>=beforeBalance-amount,"Unsupported sender surcharge");
    }
}
