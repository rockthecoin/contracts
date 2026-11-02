// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct RoleGrant { address account; uint8 mask; }
struct AllocationV5 { address beneficiary; uint256 amount; uint64 start; uint64 cliff; uint64 end; }
struct TokenConfigurationV5 {
    string name; string symbol; uint8 decimals;
    uint256 initialSupply; uint256 maximumSupply; address administrator;
    bool mintable; bool burnable; bool pausable; bool blocklist;
    bool permitEnabled; bool votingEnabled; bool lifetimeCap;
    uint16 transferTaxBps; uint16 buyTaxBps; uint16 sellTaxBps; uint16 maximumTaxBps;
    bool mutableTax; bool mutableRecipients; bool mutablePools;
    address[] taxRecipients; uint16[] taxShares; address[] taxExemptions; address[] pools;
    uint256 maximumTransaction; uint256 maximumWallet; uint32 cooldown; uint64 tradingStarts;
    bool mutableLimits; bool mutableTrading; address[] limitExemptions;
    RoleGrant[] roles;
}
