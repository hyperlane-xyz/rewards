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

        // Operator address
        address operator = 0xBf27953d8cEec841537eF039284d41b8Ea3e454D;

        // Send 0.001 ETH to the operator
        (bool success, ) = operator.call{value: 0.001 ether}("");
        require(success, "Failed to send ETH to operator");

        vm.stopBroadcast();

        // Enroll the operator
        vm.startBroadcast(vm.rememberKey(vm.envUint("OPERATOR_PRIVATE_KEY")));
        IOperatorRegistry operatorRegistry = IOperatorRegistry(0xAd817a6Bc954F678451A71363f04150FDD81Af9F);
        operatorRegistry.registerOperator();

        vm.stopBroadcast();
    }
}
