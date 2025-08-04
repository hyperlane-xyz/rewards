// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

import {IOperatorRegistry} from "lib/core/src/interfaces/IOperatorRegistry.sol";

contract EnrollOperator is Script {
    function _start() internal returns (address) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);
        return deployer;
    }

    function run() public {
        address deployer = _start();
    }
}
