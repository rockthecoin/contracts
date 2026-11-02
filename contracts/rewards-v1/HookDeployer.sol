// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
contract HookDeployer is Ownable2Step {
    event HookDeployed(address indexed hook,bytes32 indexed salt,bytes32 codeHash);
    constructor(address initialOwner) Ownable(initialOwner) {}
    function deploy(bytes32 salt,bytes calldata creationCode) external onlyOwner returns(address hook){
        bytes memory code=creationCode;assembly("memory-safe"){hook:=create2(0,add(code,32),mload(code),salt)}require(hook!=address(0),"Deployment failed");emit HookDeployed(hook,salt,keccak256(code));
    }
}
