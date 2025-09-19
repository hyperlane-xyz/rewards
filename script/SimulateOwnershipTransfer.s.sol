// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ProxyAdmin, Ownable} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {HypMinter} from "../src/contracts/HypMinter.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract SimulateOwnershipTransfer is Script, Test {
    HypMinter hypMinter = HypMinter(0x33a9e84C4437599d2317E6A4e4BEbfFe7fD57E5A);
    ProxyAdmin proxyAdmin = ProxyAdmin(0x757FFD13fCae310C084D186e2931141310514B85);
    ITransparentUpgradeableProxy proxy;

    // Admin addresses
    AccessManager accessManager = AccessManager(0x3D079E977d644c914a344Dcb5Ba54dB243Cc4863);
    TimelockController accessManagerAdmin = TimelockController(payable(0xfA842f02439Af6d91d7D44525956F9E5e00e339f));
    address multisigB = 0xec2EdC01a2Fbade68dBcc80947F43a5B408cC3A0;
    address awMultisig = 0x562Dfaac27A84be6C96273F5c9594DA1681C0DA7;

    function setUp() public {
        vm.createSelectFork("mainnet", 23378393 + 1);
        proxy = ITransparentUpgradeableProxy(address(hypMinter));
    }

    function run() public {
        vm.startBroadcast(multisigB);
        schedule();
        vm.stopBroadcast();
        skip(accessManagerAdmin.getMinDelay());
        vm.prank(makeAddr("alice"));
        accessManagerAdmin.execute({
            target: address(accessManager),
            value: 0,
            payload: accessManagerExecuteData,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });
        test_ownershipTransfer();
    }

    bytes transferOwnershipData;
    bytes accessManagerExecuteData;

    function schedule() public {
         // There's three layers here. The Ownable.transferOwnership call and the AccessManager.execute() and the 
         // AccessManagerAdmin.schedule()
        transferOwnershipData = abi.encodeCall(Ownable.transferOwnership, (awMultisig));
        accessManagerExecuteData = abi.encodeCall(accessManager.execute, (address(proxyAdmin), transferOwnershipData));
        accessManagerAdmin.schedule({
            target: address(accessManager),
            value: 0,
            data: accessManagerExecuteData,
            predecessor: bytes32(0),
            salt: bytes32(0),
            delay: accessManagerAdmin.getMinDelay()
        });
        console2.log("Scheduled ownership transfer to awMultisig:", awMultisig);
    }

    function test_ownershipTransfer() public {
        console2.log("\n=== Testing Ownership Transfer ===");
        assertEq(proxyAdmin.owner(), awMultisig);
    }

}
