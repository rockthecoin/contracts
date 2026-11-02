// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

struct TokenConfiguration {
    string name;
    string symbol;
    uint8 decimals;
    uint256 initialSupply;
    uint256 maximumSupply;
    address recipient;
    address administrator;
    bool mintable;
    bool burnable;
    bool pausable;
    bool blocklist;
    uint16 taxBps;
    uint16 maximumTaxBps;
    address taxRecipient;
    bool mutableTax;
    address[] taxExemptions;
}

/// @notice Configurable ERC20 with a permanent supply cap and explicit administrator powers.
/// @dev Permissions: mint=1, pause=2, blocklist=4, tax=8. Owner can assign/revoke them.
contract ConfigurableToken is ERC20, Ownable2Step {
    uint8 private immutable tokenDecimals;
    uint256 public immutable maximumSupply;
    bool public immutable mintable;
    bool public immutable burnable;
    bool public immutable pausable;
    bool public immutable blocklistEnabled;
    bool public immutable mutableTax;
    uint16 public immutable maximumTaxBps;
    uint16 public taxBps;
    address public taxRecipient;
    bool public paused;
    mapping(address => bool) public blocked;
    mapping(address => bool) public taxExempt;
    mapping(address => uint8) public permissions;
    uint256 public permissionedAccounts;

    event PermissionsChanged(address indexed account, uint8 permissions);
    event AccountBlocked(address indexed account, bool blocked);
    event PauseChanged(bool paused);
    event TaxChanged(uint16 basisPoints, address indexed recipient);
    event TaxExemptionChanged(address indexed account, bool exempt);
    error DisabledFeature();
    error Unauthorized();
    error InvalidConfiguration();
    error SupplyCapExceeded();
    error TransfersPaused();
    error BlockedAccount();
    error DelegatedPermissionsRemain();

    constructor(TokenConfiguration memory c) ERC20(c.name,c.symbol) Ownable(msg.sender) {
        if(bytes(c.name).length==0 || bytes(c.name).length>32 || bytes(c.symbol).length==0 || bytes(c.symbol).length>10 ||
           c.decimals>18 || c.recipient==address(0) || c.maximumSupply==0 || c.initialSupply>c.maximumSupply ||
           (!c.mintable && c.initialSupply!=c.maximumSupply) || c.maximumTaxBps>2500 || c.taxBps>c.maximumTaxBps ||
           ((c.maximumTaxBps>0 || c.mutableTax) && c.taxRecipient==address(0)) || c.taxExemptions.length>100 ||
           ((c.mintable || c.pausable || c.blocklist || c.mutableTax || c.taxRecipient!=address(0)) && c.administrator==address(0))) revert InvalidConfiguration();
        tokenDecimals=c.decimals;maximumSupply=c.maximumSupply;mintable=c.mintable;burnable=c.burnable;
        pausable=c.pausable;blocklistEnabled=c.blocklist;mutableTax=c.mutableTax;maximumTaxBps=c.maximumTaxBps;
        taxBps=c.taxBps;taxRecipient=c.taxRecipient;
        for(uint256 i=0;i<c.taxExemptions.length;i++){
            if(c.taxExemptions[i]==address(0))revert InvalidConfiguration();
            taxExempt[c.taxExemptions[i]]=true;emit TaxExemptionChanged(c.taxExemptions[i],true);
        }
        _transferOwnership(c.administrator);
        if(c.initialSupply>0)_mint(c.recipient,c.initialSupply);
    }
    function decimals() public view override returns(uint8){return tokenDecimals;}
    function hasPermission(address account,uint8 permission) public view returns(bool){return account==owner() || permissions[account]&permission!=0;}
    function setPermissions(address account,uint8 mask) external onlyOwner {
        if(account==address(0) || mask>15 || (!mintable && mask&1!=0) || (!pausable && mask&2!=0) ||
           (!blocklistEnabled && mask&4!=0) || (taxRecipient==address(0) && mask&8!=0))revert InvalidConfiguration();
        if(permissions[account]==0 && mask!=0)permissionedAccounts++;
        if(permissions[account]!=0 && mask==0)permissionedAccounts--;
        permissions[account]=mask;emit PermissionsChanged(account,mask);
    }
    function mint(address to,uint256 amount) external {
        if(!mintable)revert DisabledFeature();if(!hasPermission(msg.sender,1))revert Unauthorized();
        if(amount>maximumSupply-totalSupply())revert SupplyCapExceeded();_mint(to,amount);
    }
    function burn(uint256 amount) external {if(!burnable)revert DisabledFeature();_burn(msg.sender,amount);}
    function burnFrom(address account,uint256 amount) external {
        if(!burnable)revert DisabledFeature();_spendAllowance(account,msg.sender,amount);_burn(account,amount);
    }
    function setPaused(bool value) external {
        if(!pausable)revert DisabledFeature();if(!hasPermission(msg.sender,2))revert Unauthorized();paused=value;emit PauseChanged(value);
    }
    function setBlocked(address account,bool value) external {
        if(!blocklistEnabled)revert DisabledFeature();if(!hasPermission(msg.sender,4))revert Unauthorized();
        if(account==address(0))revert InvalidConfiguration();blocked[account]=value;emit AccountBlocked(account,value);
    }
    function setTax(uint16 rate,address recipient) external {
        if(!mutableTax)revert DisabledFeature();if(!hasPermission(msg.sender,8))revert Unauthorized();
        if(rate>maximumTaxBps || recipient==address(0))revert InvalidConfiguration();taxBps=rate;taxRecipient=recipient;emit TaxChanged(rate,recipient);
    }
    function setTaxExempt(address account,bool value) external {
        if(taxRecipient==address(0))revert DisabledFeature();if(!hasPermission(msg.sender,8))revert Unauthorized();
        if(account==address(0))revert InvalidConfiguration();taxExempt[account]=value;emit TaxExemptionChanged(account,value);
    }
    function renounceOwnership() public override onlyOwner {
        if(permissionedAccounts!=0)revert DelegatedPermissionsRemain();super.renounceOwnership();
    }
    function _update(address from,address to,uint256 value) internal override {
        if(paused)revert TransfersPaused();
        if(blocklistEnabled && ((from!=address(0) && blocked[from]) || (to!=address(0) && blocked[to])))revert BlockedAccount();
        if(from!=address(0) && to!=address(0) && from!=to && taxBps!=0 && !taxExempt[from] && !taxExempt[to]){
            uint256 fee=(value/10000)*taxBps+((value%10000)*taxBps)/10000;
            if(fee>0){if(blocklistEnabled && blocked[taxRecipient])revert BlockedAccount();super._update(from,taxRecipient,fee);}
            super._update(from,to,value-fee);
        }else super._update(from,to,value);
    }
}
