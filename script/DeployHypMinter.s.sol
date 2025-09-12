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
 * forge script script/DeployHypMinter.s.sol:DeployHypMinter --sig "run(uint256,uint256)" 1760742887 518400 --rpc-url $RPC_URL --broadcast --verify
 * 
 * Environment Variables:
 * - DEPLOYER_PRIVATE_KEY: Private key for deployment
 * - ETHERSCAN_API_KEY: For contract verification
 */
contract DeployHypMinter is Script {
    // Constructor Constants
    uint256 constant DISTRIBUTION_DELAY_MAXIMUM = 7 days;
    
    // Deployment configuration => pass to initialize
    struct DeployConfig {
        uint256 firstRewardTimestamp;
        uint256 mintAllowedTimestamp;
        uint256 distributionDelay;
        AccessManager accessManager;
    }
    
    function run(uint256 _firstRewardTimestamp, uint256 _mintAllowedTimestamp, uint256 _distributionDelay, AccessManager _accessManager) public {
        require(_distributionDelay <= DISTRIBUTION_DELAY_MAXIMUM, "Distribution delay too large");
        require(_mintAllowedTimestamp > block.timestamp, "Mint allowed timestamp must be in future");
        

        DeployConfig memory config = DeployConfig({
            firstRewardTimestamp: _firstRewardTimestamp,
            mintAllowedTimestamp: _mintAllowedTimestamp,
            distributionDelay: _distributionDelay,
            accessManager: _accessManager
        });
        
        _deploy(config);
    }
    
    function _deploy(DeployConfig memory config) internal {
        // Start broadcast
        address deployer = _getDeployer();
        vm.startBroadcast(deployer);
        
        // Deploy implementation
        console2.log("Deploying HypMinter implementation...");
        HypMinter implementation = new HypMinter(DISTRIBUTION_DELAY_MAXIMUM);
        console2.log("Implementation deployed at:", address(implementation));
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            HypMinter.initialize,
            (
                config.firstRewardTimestamp,
                config.mintAllowedTimestamp,
                AccessManager(config.accessManager),
                config.distributionDelay
            )
        );
        
        // Deploy proxy with deployer as proxy admin
        console2.log("Deploying TransparentUpgradeableProxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer, // Use deployer as proxy admin
            initData
        );
        console2.log("Proxy deployed at:", address(proxy));
        
        // Get the proxied contract
        HypMinter hypMinter = HypMinter(address(proxy));
        
        vm.stopBroadcast();
        
        // Log deployment summary
        logDeploymentSummary(hypMinter, implementation, config);
        
        // Verify deployment
        verifyDeployment(hypMinter, config);
    }
    
    
    function logDeploymentSummary(
        HypMinter hypMinter,
        HypMinter implementation,
        DeployConfig memory config
    ) internal {
        console2.log("\n=== HypMinter Deployment Summary ===");
        console2.log("Implementation:", address(implementation));
        console2.log("Proxy (HypMinter):", address(hypMinter));
        console2.log("Proxy Admin:", _getDeployer());
        console2.log("Access Manager:", address(config.accessManager));
        console2.log("");
        
        console2.log("=== Configuration ===");
        console2.log("First Reward Timestamp:", config.firstRewardTimestamp);
        console2.log("Mint Allowed Timestamp:", config.mintAllowedTimestamp);
        console2.log("Distribution Delay Maximum:", hypMinter.distributionDelayMaximum(), "seconds");
        console2.log("Distribution Delay:", config.distributionDelay, "seconds");
        console2.log("");
        
        console2.log("=== Contract Constants ===");
        console2.log("HYPER Token:", address(hypMinter.HYPER()));
        console2.log("Rewards Contract:", address(hypMinter.REWARDS()));
        console2.log("Symbiotic Network:", hypMinter.SYMBIOTIC_NETWORK());
        console2.log("Mint Amount per Epoch:", hypMinter.MINT_AMOUNT() / 1e18, "HYPER");
        console2.log("");
        
        console2.log("=== Initial Settings ===");
        console2.log("Operator BPS:", hypMinter.operatorBps(), "basis points");
        console2.log("Operator Manager:", hypMinter.operatorRewardsManager());
        console2.log("Distribution Delay:", hypMinter.distributionDelay(), "seconds");
        console2.log("");
        
        console2.log("=== Next Steps ===");
        console2.log("1. Set middleware: Call networkMiddlewareService.setMiddleware(address(hypMinter))");
        console2.log("2. Grant MINTER_ROLE: Call HYPER.grantRole(keccak256('MINTER_ROLE'), address(hypMinter))");
        console2.log("3. Wait for mint allowed timestamp:", config.mintAllowedTimestamp);
        console2.log("4. Start minting epochs every 30 days");
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
