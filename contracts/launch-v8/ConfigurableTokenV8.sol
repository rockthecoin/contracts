// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {TokenConfigurationV8,RoleGrant} from "./LaunchTypes.sol";

/// @notice Non-upgradeable ERC20. Cap, feature availability and change permissions are permanent.
contract ConfigurableTokenV8 is ERC20,ERC20Permit,ERC20Votes,Ownable2Step {
    uint8 private immutable tokenDecimals;
    uint256 public immutable maximumSupply;
    bool public immutable mintable; bool public immutable burnable; bool public immutable pausable;
    bool public immutable blocklistEnabled; bool public immutable permitEnabled; bool public immutable votingEnabled;
    bool public immutable lifetimeCap; bool public immutable mutableTax; bool public immutable mutableRecipients;
    bool public immutable mutablePools; bool public immutable mutableLimits; bool public immutable mutableTrading;
    uint16 public immutable maximumTaxBps;
    address public immutable allocationFactory;
    uint256 public totalMinted; bool public distributionFinished; bool public paused;
    uint16 public taxBps; uint16 public buyTaxBps; uint16 public sellTaxBps;
    address[] public taxRecipients; uint16[] public taxShares;
    uint256 public maximumTransaction; uint256 public maximumWallet; uint32 public cooldown; uint64 public tradingStarts;
    mapping(address=>bool) public blocked; mapping(address=>bool) public taxExempt;
    mapping(address=>bool) public ammPools; mapping(address=>bool) public limitExempt;
    mapping(address=>uint64) public lastTransferAt; mapping(address=>uint8) public permissions;
    uint256 public permissionedAccounts;uint256 public poolCount;
    // Permission bits: mint=1, pause=2, blocklist=4, tax/pools=8, limits=16, trading=32.
    event PermissionsChanged(address indexed account,uint8 permissions);
    event AccountBlocked(address indexed account,bool blocked); event PauseChanged(bool paused);
    event TaxRatesChanged(uint16 transferRate,uint16 buyRate,uint16 sellRate);
    event TaxRecipientsChanged(address[] recipients,uint16[] shares);
    event TaxExemptionChanged(address indexed account,bool exempt); event PoolChanged(address indexed pool,bool enabled);
    event LimitsChanged(uint256 maximumTransaction,uint256 maximumWallet,uint32 cooldown);
    event LimitExemptionChanged(address indexed account,bool exempt); event TradingStartChanged(uint64 timestamp);
    error DisabledFeature(); error Unauthorized(); error InvalidConfiguration(); error SupplyCapExceeded();
    error TransfersPaused(); error BlockedAccount(); error TransferRestricted(); error DelegatedPermissionsRemain();
    constructor(TokenConfigurationV8 memory c,address distributor)
        ERC20(c.name,c.symbol) ERC20Permit(c.name) Ownable(msg.sender) {
        if(bytes(c.name).length==0||bytes(c.name).length>32||bytes(c.symbol).length==0||bytes(c.symbol).length>10||c.decimals>18||
           distributor==address(0)||c.maximumSupply==0||c.initialSupply>c.maximumSupply||(!c.mintable&&c.initialSupply!=c.maximumSupply)||
           c.maximumTaxBps>2500||c.transferTaxBps>c.maximumTaxBps||c.buyTaxBps>c.maximumTaxBps||c.sellTaxBps>c.maximumTaxBps||
           (c.votingEnabled&&c.maximumSupply>type(uint208).max)||c.taxExemptions.length>100||c.limitExemptions.length>100||c.pools.length>100||c.roles.length>32)
            revert InvalidConfiguration();
        bool taxed=c.taxRecipients.length!=0;
        if((c.mintable||c.pausable||c.blocklist||taxed||c.mutableLimits||c.mutableTrading||c.mutablePools||c.roles.length!=0)&&c.administrator==address(0))revert InvalidConfiguration();
        if(!taxed&&(c.maximumTaxBps!=0||c.transferTaxBps!=0||c.buyTaxBps!=0||c.sellTaxBps!=0||c.mutableTax||c.mutableRecipients))revert InvalidConfiguration();
        if((c.buyTaxBps!=c.transferTaxBps||c.sellTaxBps!=c.transferTaxBps||c.tradingStarts!=0)&&c.pools.length==0&&!c.mutablePools)revert InvalidConfiguration();
        tokenDecimals=c.decimals;maximumSupply=c.maximumSupply;mintable=c.mintable;burnable=c.burnable;pausable=c.pausable;
        blocklistEnabled=c.blocklist;permitEnabled=c.permitEnabled;votingEnabled=c.votingEnabled;lifetimeCap=c.lifetimeCap;
        mutableTax=c.mutableTax;mutableRecipients=c.mutableRecipients;mutablePools=c.mutablePools;
        mutableLimits=c.mutableLimits;mutableTrading=c.mutableTrading;maximumTaxBps=c.maximumTaxBps;allocationFactory=distributor;
        taxBps=c.transferTaxBps;buyTaxBps=c.buyTaxBps;sellTaxBps=c.sellTaxBps;
        _recipients(c.taxRecipients,c.taxShares);_limits(c.maximumTransaction,c.maximumWallet,c.cooldown);tradingStarts=c.tradingStarts;
        for(uint256 i;i<c.taxExemptions.length;i++){_nonzero(c.taxExemptions[i]);taxExempt[c.taxExemptions[i]]=true;}
        for(uint256 i;i<c.limitExemptions.length;i++){_nonzero(c.limitExemptions[i]);limitExempt[c.limitExemptions[i]]=true;}
        for(uint256 i;i<c.pools.length;i++){_nonzero(c.pools[i]);if(!ammPools[c.pools[i]])poolCount++;ammPools[c.pools[i]]=true;}
        _transferOwnership(c.administrator);
        for(uint256 i;i<c.roles.length;i++)_permissions(c.roles[i].account,c.roles[i].mask);
        totalMinted=c.lifetimeCap?c.initialSupply:0;if(c.initialSupply!=0)_move(address(0),distributor,c.initialSupply);
    }
    function decimals() public view override returns(uint8){return tokenDecimals;}
    function nonces(address account) public view override(ERC20Permit,Nonces) returns(uint256){return super.nonces(account);}
    function permit(address account,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s) public override {
        if(!permitEnabled)revert DisabledFeature();super.permit(account,spender,value,deadline,v,r,s);
    }
    function _delegate(address account,address delegatee) internal override {if(!votingEnabled)revert DisabledFeature();super._delegate(account,delegatee);}
    function hasPermission(address account,uint8 mask) public view returns(bool){return account==owner()||permissions[account]&mask!=0;}
    function _requirePermission(uint8 mask) private view {if(!hasPermission(msg.sender,mask))revert Unauthorized();}
    function _nonzero(address account) private pure {if(account==address(0))revert InvalidConfiguration();}
    function _permissions(address account,uint8 mask) private {
        _nonzero(account);
        if(mask>63||(!mintable&&mask&1!=0)||(!pausable&&mask&2!=0)||(!blocklistEnabled&&mask&4!=0)||
           (taxRecipients.length==0&&!mutablePools&&mask&8!=0)||(!mutableLimits&&mask&16!=0)||(!mutableTrading&&mask&32!=0))revert InvalidConfiguration();
        if(permissions[account]==0&&mask!=0)permissionedAccounts++;if(permissions[account]!=0&&mask==0)permissionedAccounts--;
        permissions[account]=mask;emit PermissionsChanged(account,mask);
    }
    function setPermissions(address account,uint8 mask) external onlyOwner {_permissions(account,mask);}
    function distributeInitial(address recipient,uint256 amount) external {
        if(msg.sender!=allocationFactory||distributionFinished)revert Unauthorized();_nonzero(recipient);_move(allocationFactory,recipient,amount);
    }
    function finishDistribution() external {
        if(msg.sender!=allocationFactory||distributionFinished||balanceOf(allocationFactory)!=0)revert Unauthorized();distributionFinished=true;
    }
    function mint(address to,uint256 amount) external {
        if(!mintable)revert DisabledFeature();_requirePermission(1);
        if(amount>maximumSupply-(lifetimeCap?totalMinted:totalSupply()))revert SupplyCapExceeded();if(lifetimeCap)totalMinted+=amount;_mint(to,amount);
    }
    function burn(uint256 amount) external {if(!burnable)revert DisabledFeature();_burn(msg.sender,amount);}
    function burnFrom(address account,uint256 amount) external {if(!burnable)revert DisabledFeature();_spendAllowance(account,msg.sender,amount);_burn(account,amount);}
    function setPaused(bool value) external {if(!pausable)revert DisabledFeature();_requirePermission(2);paused=value;emit PauseChanged(value);}
    function setBlocked(address account,bool value) external {if(!blocklistEnabled)revert DisabledFeature();_requirePermission(4);_nonzero(account);blocked[account]=value;emit AccountBlocked(account,value);}
    function taxRecipient() public view returns(address){return taxRecipients.length==0?address(0):taxRecipients[0];}
    function taxRecipientCount() external view returns(uint256){return taxRecipients.length;}
    function setTaxRates(uint16 transferRate,uint16 buyRate,uint16 sellRate) external {
        if(!mutableTax)revert DisabledFeature();_requirePermission(8);
        if(transferRate>maximumTaxBps||buyRate>maximumTaxBps||sellRate>maximumTaxBps||((buyRate!=transferRate||sellRate!=transferRate)&&poolCount==0&&!mutablePools))revert InvalidConfiguration();
        taxBps=transferRate;buyTaxBps=buyRate;sellTaxBps=sellRate;emit TaxRatesChanged(transferRate,buyRate,sellRate);
    }
    function _recipients(address[] memory accounts,uint16[] memory shares) private {
        if(accounts.length!=shares.length||accounts.length>5)revert InvalidConfiguration();uint256 total;
        for(uint256 i;i<accounts.length;i++){_nonzero(accounts[i]);if(shares[i]==0)revert InvalidConfiguration();for(uint256 j;j<i;j++)if(accounts[j]==accounts[i])revert InvalidConfiguration();total+=shares[i];}
        if(accounts.length!=0&&total!=10000)revert InvalidConfiguration();taxRecipients=accounts;taxShares=shares;emit TaxRecipientsChanged(accounts,shares);
    }
    function setTaxRecipients(address[] calldata accounts,uint16[] calldata shares) external {
        if(!mutableRecipients)revert DisabledFeature();_requirePermission(8);if(accounts.length==0)revert InvalidConfiguration();_recipients(accounts,shares);
    }
    function setTaxExempt(address account,bool value) external {if(taxRecipients.length==0)revert DisabledFeature();_requirePermission(8);_nonzero(account);taxExempt[account]=value;emit TaxExemptionChanged(account,value);}
    function setPool(address account,bool value) external {if(!mutablePools)revert DisabledFeature();_requirePermission(8);_nonzero(account);if(value&&!ammPools[account])poolCount++;if(!value&&ammPools[account])poolCount--;ammPools[account]=value;emit PoolChanged(account,value);}
    function _limits(uint256 transactionLimit,uint256 walletLimit,uint32 delay) private {
        if(transactionLimit>maximumSupply||walletLimit>maximumSupply||delay>30 days)revert InvalidConfiguration();
        maximumTransaction=transactionLimit;maximumWallet=walletLimit;cooldown=delay;emit LimitsChanged(transactionLimit,walletLimit,delay);
    }
    function setLimits(uint256 transactionLimit,uint256 walletLimit,uint32 delay) external {if(!mutableLimits)revert DisabledFeature();_requirePermission(16);_limits(transactionLimit,walletLimit,delay);}
    function setLimitExempt(address account,bool value) external {if(!mutableLimits)revert DisabledFeature();_requirePermission(16);_nonzero(account);limitExempt[account]=value;emit LimitExemptionChanged(account,value);}
    function setTradingStart(uint64 timestamp) external {if(!mutableTrading)revert DisabledFeature();_requirePermission(32);tradingStarts=timestamp;emit TradingStartChanged(timestamp);}
    function renounceOwnership() public override onlyOwner {if(paused)revert TransfersPaused();if(permissionedAccounts!=0)revert DelegatedPermissionsRemain();super.renounceOwnership();}
    function _fraction(uint256 value,uint16 bps) private pure returns(uint256){return(value/10000)*bps+((value%10000)*bps)/10000;}
    function _move(address from,address to,uint256 amount) private {if(votingEnabled)ERC20Votes._update(from,to,amount);else ERC20._update(from,to,amount);}
    function _checkWalletLimit(address account) private view {
        if(account!=address(0)&&!ammPools[account]&&!limitExempt[account]&&maximumWallet!=0&&balanceOf(account)>maximumWallet)revert TransferRestricted();
    }
    function _update(address from,address to,uint256 value) internal override(ERC20,ERC20Votes) {
        if(!distributionFinished)revert TransferRestricted();if(paused)revert TransfersPaused();
        if(blocklistEnabled&&((from!=address(0)&&blocked[from])||(to!=address(0)&&blocked[to])))revert BlockedAccount();
        bool transfer=value!=0&&from!=address(0)&&to!=address(0)&&from!=to;
        uint256 fee;
        if(transfer&&!taxExempt[from]&&!taxExempt[to])fee=_fraction(value,ammPools[to]?sellTaxBps:ammPools[from]?buyTaxBps:taxBps);
        if(transfer&&!limitExempt[from]&&!limitExempt[to]){
            if((ammPools[from]||ammPools[to])&&block.timestamp<tradingStarts)revert TransferRestricted();
            if(maximumTransaction!=0&&value>maximumTransaction)revert TransferRestricted();
            if(cooldown!=0&&!ammPools[from]){if(lastTransferAt[from]!=0&&block.timestamp<uint256(lastTransferAt[from])+cooldown)revert TransferRestricted();lastTransferAt[from]=uint64(block.timestamp);}
        }
        uint256[5] memory credits;
        if(fee!=0){uint256 remaining=fee;for(uint256 i;i<taxRecipients.length;i++){
            address recipient=taxRecipients[i];if(blocklistEnabled&&blocked[recipient])revert BlockedAccount();
            uint256 portion=i+1==taxRecipients.length?remaining:_fraction(fee,taxShares[i]);remaining-=portion;credits[i]=portion;if(portion!=0)_move(from,recipient,portion);
        }}
        _move(from,to,value-fee);
        // Check complete final balances, including a tax share paid to `to`.
        // A sender returning its own tax share has no net increase. Initial
        // allocations may exceed a wallet cap, so that sender must remain able to exit.
        if(from!=to)_checkWalletLimit(to);
        if(fee!=0)for(uint256 i;i<taxRecipients.length;i++){
            address recipient=taxRecipients[i];if(credits[i]!=0&&recipient!=from&&recipient!=to)_checkWalletLimit(recipient);
        }
    }
}
