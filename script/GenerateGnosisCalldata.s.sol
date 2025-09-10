// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {HypMinter} from "../src/contracts/HypMinter.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {NetworkMiddlewareService} from "../lib/core/src/contracts/service/NetworkMiddlewareService.sol";

/**
 * @title Generate Gnosis Safe Calldata
 * @dev Script to generate calldata for Gnosis Safe transactions for HypMinter operations
 * 
 * Usage:
 * // HypMinter configuration
 * forge script script/GenerateGnosisCalldata.s.sol:GenerateGnosisCalldata --sig "generateSetOperatorBps(uint256)" 1500
 * forge script script/GenerateGnosisCalldata.s.sol:GenerateGnosisCalldata --sig "generateSetDistributionDelay(uint256)" 259200
 * 
 * // Middleware setup (2-step process)
 * forge script script/GenerateGnosisCalldata.s.sol:GenerateGnosisCalldata --sig "generateSetMiddlewareSchedule(address,uint48)" 0xHypMinterAddress 1234567890
 * forge script script/GenerateGnosisCalldata.s.sol:GenerateGnosisCalldata --sig "generateSetMiddlewareExecute(address)" 0xHypMinterAddress
 * 
 * // Helpers
 * forge script script/GenerateGnosisCalldata.s.sol:GenerateGnosisCalldata --sig "timeToSeconds()"
 */
contract GenerateGnosisCalldata is Script {
    // Mainnet addresses from the test file
    address HYPMINTER_ADDRESS = makeAddr("hypMinter"); // Replace with actual deployed HypMinter address
    address constant ACCESS_MANAGER = 0x3D079E977d644c914a344Dcb5Ba54dB243Cc4863;
    address constant SYMBIOTIC_NETWORK = 0x59cf937Ea9FA9D7398223E3aA33d92F7f5f986A2;
    address constant NETWORK_MIDDLEWARE_SERVICE = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;
    
    function generateSetOperatorBps(uint256 newBps) external  {
        bytes memory callData = abi.encodeCall(HypMinter.setOperatorRewardsBps, (newBps));
        
        console2.log("=== Gnosis Safe Transaction Data ===");
        console2.log("Target Contract:", HYPMINTER_ADDRESS);
        console2.log("Function: setOperatorRewardsBps(uint256)");
        console2.log("Parameter - newBps:", newBps);
        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("Calldata (hex):", vm.toString(callData));
    }
    
    function generateSetOperatorManager(address newManager) external  {
        bytes memory callData = abi.encodeCall(HypMinter.setOperatorRewardsManager, (newManager));
        
        console2.log("=== Gnosis Safe Transaction Data ===");
        console2.log("Target Contract:", HYPMINTER_ADDRESS);
        console2.log("Function: setOperatorRewardsManager(address)");
        console2.log("Parameter - newManager:", newManager);
        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("Calldata (hex):", vm.toString(callData));
    }
    
    function generateSetDistributionDelay(uint256 delaySeconds) external  {
        bytes memory callData = abi.encodeCall(HypMinter.setDistributionDelay, (delaySeconds));
        
        console2.log("=== Gnosis Safe Transaction Data ===");
        console2.log("Target Contract:", HYPMINTER_ADDRESS);
        console2.log("Function: setDistributionDelay(uint256)");
        console2.log("Parameter - delaySeconds:", delaySeconds);
        console2.log("Parameter - delayDays:", delaySeconds / 86400);
        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("Calldata (hex):", vm.toString(callData));
    }
    
    function generateBatchTransaction() external  {
        // Example: Set operator BPS to 15% and distribution delay to 3 days
        bytes memory call1 = abi.encodeCall(HypMinter.setOperatorRewardsBps, (1500));
        bytes memory call2 = abi.encodeCall(HypMinter.setDistributionDelay, (3 days));
        
        console2.log("=== Gnosis Safe Batch Transaction ===");
        console2.log("Target Contract:", HYPMINTER_ADDRESS);
        console2.log("");
        
        console2.log("Transaction 1:");
        console2.log("Function: setOperatorRewardsBps(uint256)");
        console2.log("Calldata (hex):", vm.toString(call1));
        console2.log("");
        
        console2.log("Transaction 2:");
        console2.log("Function: setDistributionDelay(uint256)");
        console2.log("Calldata (hex):", vm.toString(call2));
        
        console2.log("");
        console2.log("=== For MultiSend (if using batch) ===");
        // MultiSend encoding: operation(1) + to(20) + value(32) + dataLength(32) + data
        bytes memory multiSendData = abi.encodePacked(
            uint8(0), // operation: 0 = call
            HYPMINTER_ADDRESS, // to
            uint256(0), // value
            uint256(call1.length), // data length
            call1, // data
            uint8(0), // operation: 0 = call  
            HYPMINTER_ADDRESS, // to
            uint256(0), // value
            uint256(call2.length), // data length
            call2 // data
        );
        console2.log("MultiSend Data:");
        console2.logBytes(multiSendData);
    }
    
    /**
     * @notice Generate calldata for scheduling setMiddleware call on the network via AccessManager
     * @param hypMinterAddress The address of the deployed HypMinter contract
     * @param when The timestamp when the scheduled transaction can be executed (block.timestamp + delay)
     * @dev This generates the exact calldata needed for the Gnosis Safe to call accessManager.schedule
     */
    function generateSetMiddlewareSchedule(address hypMinterAddress, uint48 when) external  {
        // Step 1: Encode the setMiddleware call
        bytes memory setMiddlewareData = abi.encodeCall(
            NetworkMiddlewareService.setMiddleware, 
            (hypMinterAddress)
        );
        
        // Step 2: Encode the TimelockController.schedule call for the network
        bytes memory networkScheduleData = abi.encodeCall(
            TimelockController.schedule,
            (
                NETWORK_MIDDLEWARE_SERVICE,  // target: NetworkMiddlewareService
                0,                           // value: 0 ETH
                setMiddlewareData,          // data: setMiddleware call
                bytes32(0),                 // predecessor: none
                bytes32(0),                 // salt: none  
                0 days                      // delay: 0 days (already scheduled via AccessManager)
            )
        );
        
        // Step 3: Encode the AccessManager.schedule call (this is what the Safe will call)
        bytes memory accessManagerScheduleData = abi.encodeCall(
            AccessManager.schedule,
            (
                SYMBIOTIC_NETWORK,          // target: The Symbiotic Network (TimelockController)
                networkScheduleData,        // data: The network schedule call
                when                        // when: Timestamp when execution is allowed
            )
        );
        
        console2.log("=== Gnosis Safe Transaction: Schedule setMiddleware ===");
        console2.log("Target Contract (AccessManager):", ACCESS_MANAGER);
        console2.log("HypMinter Address:", hypMinterAddress);
        console2.log("Execution Timestamp (when):", when);
        console2.log("Execution Delay from now (assuming current time):", when - uint48(vm.getBlockTimestamp()), "seconds");
        console2.log("");
        
        console2.log("=== Breakdown ===");
        console2.log("1. setMiddleware call data:");
        console2.logBytes(setMiddlewareData);
        console2.log("");
        
        console2.log("2. Network schedule call data:");
        console2.logBytes(networkScheduleData);
        console2.log("");
        
        console2.log("3. FINAL CALLDATA for Gnosis Safe:");
        console2.log("Function: AccessManager.schedule(address,bytes,uint48)");
        console2.logBytes(accessManagerScheduleData);
        console2.log("Calldata (hex):", vm.toString(accessManagerScheduleData));
        console2.log("");
        
        console2.log("=== Instructions ===");
        console2.log("1. Submit this transaction to Gnosis Safe");
        console2.log("2. Wait for the delay period (7 days typically)");
        console2.log("3. Then execute with generateSetMiddlewareExecute()");
    }
    
    /**
     * @notice Generate calldata for executing the scheduled setMiddleware call
     * @param hypMinterAddress The address of the deployed HypMinter contract
     * @dev This generates the calldata for the execution step after the delay has passed
     */
    function generateSetMiddlewareExecute(address hypMinterAddress) external  {
        // Step 1: Encode the setMiddleware call (same as in schedule)
        bytes memory setMiddlewareData = abi.encodeCall(
            NetworkMiddlewareService.setMiddleware, 
            (hypMinterAddress)
        );
        
        // Step 2: Encode the TimelockController.schedule call for the network (same as in schedule)
        bytes memory networkScheduleData = abi.encodeCall(
            TimelockController.schedule,
            (
                NETWORK_MIDDLEWARE_SERVICE,  // target: NetworkMiddlewareService
                0,                           // value: 0 ETH
                setMiddlewareData,          // data: setMiddleware call
                bytes32(0),                 // predecessor: none
                bytes32(0),                 // salt: none  
                0 days                      // delay: 0 days
            )
        );
        
        // Step 3: Encode the AccessManager.execute call
        bytes memory accessManagerExecuteData = abi.encodeCall(
            AccessManager.execute,
            (
                SYMBIOTIC_NETWORK,          // target: The Symbiotic Network (TimelockController)
                networkScheduleData         // data: The network schedule call
            )
        );
        
        console2.log("=== Gnosis Safe Transaction: Execute setMiddleware ===");
        console2.log("Target Contract (AccessManager):", ACCESS_MANAGER);
        console2.log("HypMinter Address:", hypMinterAddress);
        console2.log("");
        
        console2.log("CALLDATA for Gnosis Safe:");
        console2.log("Function: AccessManager.execute(address,bytes)");
        console2.logBytes(accessManagerExecuteData);
        console2.log("Calldata (hex):", vm.toString(accessManagerExecuteData));
        console2.log("");
        
        console2.log("=== Instructions ===");
        console2.log("1. This should be called AFTER the schedule transaction");
        console2.log("2. And AFTER the delay period has passed");
        console2.log("3. This will actually execute the setMiddleware call");
    }
}
