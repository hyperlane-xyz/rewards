// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {HypMinter} from "../src/contracts/HypMinter.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title Deploy HypMinter Script
 * @dev Script to deploy HypMinter contract with proper initialization
 *
 * Usage:
 * forge script script/DeployHypMinter.s.sol:DeployHypMinter --sig "run()" --rpc-url $RPC_URL --broadcast --verify
 *
 * Environment Variables:
 * - PRIVATE_KEY: Private key for deployment
 */
contract DeployHypMinter is Script {
    // Constructor Constants
    uint256 constant DISTRIBUTION_DELAY_MAXIMUM = 10 days;

    // Deployment configuration => pass to initialize
    struct DeployConfig {
        AccessManager accessManager;
        uint256 firstRewardTimestamp;
        uint256 mintAllowedTimestamp;
        uint256 distributionAllowedTimestamp;
        uint256 distributionDelay;
        address operatorRewardsManager;
    }

    function run() public {
        uint256 distributionAllowedTimestamp = 1_761_141_600; // Wednesday, October 22, 2025 10:00:00 AM GMT-04:00
        uint256 distributionDelay = 7 days;
        run({
            _accessManager: AccessManager(0x3D079E977d644c914a344Dcb5Ba54dB243Cc4863),
            _firstRewardTimestamp: 1_752_448_487, // Sun Jul 13 2025 19:14:47 EDT
            _mintAllowedTimestamp: distributionAllowedTimestamp - distributionDelay, // Wednesday, October 15, 2025 10:00:00 AM GMT-04:00 DST
            _distributionAllowedTimestamp: distributionAllowedTimestamp,
            _distributionDelay: distributionDelay,
            _operatorRewardsManager: 0x562Dfaac27A84be6C96273F5c9594DA1681C0DA7 // Multisig A
        });
    }

    function run(
        AccessManager _accessManager,
        uint256 _firstRewardTimestamp,
        uint256 _mintAllowedTimestamp,
        uint256 _distributionAllowedTimestamp,
        uint256 _distributionDelay,
        address _operatorRewardsManager
    ) public {
        require(_distributionDelay <= DISTRIBUTION_DELAY_MAXIMUM, "Distribution delay too large");
        require(_mintAllowedTimestamp > block.timestamp, "Mint allowed timestamp must be in future");
        require(_distributionAllowedTimestamp > block.timestamp, "Distribution allowed timestamp must be in future");

        DeployConfig memory config = DeployConfig({
            firstRewardTimestamp: _firstRewardTimestamp,
            mintAllowedTimestamp: _mintAllowedTimestamp,
            distributionAllowedTimestamp: _distributionAllowedTimestamp,
            distributionDelay: _distributionDelay,
            accessManager: _accessManager,
            operatorRewardsManager: _operatorRewardsManager
        });

        _deploy(config);
    }

    function _deploy(
        DeployConfig memory config
    ) internal {
        // Start broadcast
        address deployer = _getDeployer();
        vm.startBroadcast(deployer);

        bytes32 salt = keccak256(abi.encode(config));

        // Deploy implementation
        console2.log("Deploying HypMinter implementation...");
        HypMinter implementation = new HypMinter{salt: salt}(DISTRIBUTION_DELAY_MAXIMUM);
        console2.log("Implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            HypMinter.initialize,
            (
                config.accessManager,
                config.firstRewardTimestamp,
                config.mintAllowedTimestamp,
                config.distributionAllowedTimestamp,
                config.distributionDelay,
                config.operatorRewardsManager
            )
        );

        // Deploy proxy with deployer as proxy admin
        console2.log("Deploying TransparentUpgradeableProxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{salt: salt}(
            address(implementation),
            address(config.accessManager), // Use access manager as proxy admin
            initData
        );
        console2.log("Proxy deployed at:", address(proxy));

        // Get the proxied contract
        HypMinter hypMinter = HypMinter(address(proxy));

        vm.stopBroadcast();

        // Verify deployment
        verifyDeployment(hypMinter, config);
    }

    function verifyDeployment(HypMinter hypMinter, DeployConfig memory config) internal view {
        console2.log("\n=== Deployment Verification ===");

        // Verify initialization
        require(hypMinter.lastRewardTimestamp() == config.firstRewardTimestamp, "First reward timestamp mismatch");
        require(hypMinter.mintAllowedTimestamp() == config.mintAllowedTimestamp, "Mint allowed timestamp mismatch");
        require(address(hypMinter.authority()) == address(config.accessManager), "Access manager mismatch");
        require(hypMinter.distributionDelay() == config.distributionDelay, "Distribution delay mismatch");

        // Verify HYPER approval
        require(
            hypMinter.HYPER().allowance(address(hypMinter), address(hypMinter.REWARDS())) == type(uint256).max,
            "HYPER approval not set"
        );

        console2.log("All verifications passed!");
    }

    function _getDeployer() internal returns (address) {
        return vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    }
}
