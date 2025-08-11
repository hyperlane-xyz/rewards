// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDefaultStakerRewards} from "src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {NetworkRegistry} from "lib/core/src/contracts/NetworkRegistry.sol";
import {NetworkMiddlewareService} from "lib/core/src/contracts/service/NetworkMiddlewareService.sol";
import {IVaultTokenized} from "lib/core/src/interfaces/vault/IVaultTokenized.sol";
import {console2} from "forge-std/console2.sol";

contract DistributeRewardsStaging is Script {
    function _start() internal returns (address) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);
        console2.log("deployer", deployer);
        return deployer;
    }

    function _getNetwork() internal returns (address) {
        // This is the network address, which is also just the deployer address
        return 0xfaD1C94469700833717Fa8a3017278BC1cA8031C;
    }

    function _setupNetwork() internal {
        // Register network using networkregistry at 0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9
        NetworkRegistry networkRegistry = NetworkRegistry(0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9);
        networkRegistry.registerNetwork();
    }

    function _registerMiddleware() internal {
        // Register middleware using NetworkMiddlewareService at 0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3
        NetworkMiddlewareService networkMiddlewareService = NetworkMiddlewareService(0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3);
        // The middleware is the network address, which is also just the deployer address. We're only doing this because we're just testing
        // On mainnet, use a contract the middleware
        networkMiddlewareService.setMiddleware(_getNetwork());
    }

   
    function _fundDepositor(address depositor) internal {
        ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        hyper.transfer(depositor, 0.001 ether);
    }

    function fundDepositor(address depositor) public {
        _start();
        depositor.call{value:0.01 ether}("");
        _fundDepositor(depositor);
    }

    function _deposit(address depositor) internal {
        ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        IVaultTokenized vault = IVaultTokenized(0xF56179944D867469612D138c74F1dE979D3faC72);
        hyper.approve(address(vault), type(uint256).max);

        // 1. deposit
        vault.deposit(depositor, 0.001 ether);
    }

    function deposit() public {
        address depositor = tx.origin;
        _deposit(depositor);
    }

    function _distributeRewards() internal {
        IDefaultStakerRewards rewards = IDefaultStakerRewards(0xe0bf535F776d900D499407623C03bACe81334127);
        ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        hyper.approve(address(rewards), type(uint256).max);

        // 1. distribute rewards
        uint48 timestamp = uint48(block.timestamp - 1); // Distributions must be for timestamp in the past
        rewards.distributeRewards(
            _getNetwork(),
            address(hyper), // HYPER
            0.001 ether,
            abi.encode(timestamp, 0, bytes(""), bytes(""))
        );
 
    }

    function distributeRewards() public {
        _start(); 
        _distributeRewards();
    }

    function _setupVault() internal {
        _setupNetwork();
        _registerMiddleware();
    }

    function setupVault() public {
        _start();
        _setupVault();
    }

    function claimRewards() public {
        address depositor = tx.origin;
        _start();
        IDefaultStakerRewards rewards = IDefaultStakerRewards(0xe0bf535F776d900D499407623C03bACe81334127);
        // Log some info about distributions
        address token = 0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011;
        address network = _getNetwork();
       (uint amount, uint48 timestamp1) = rewards.rewards(token,network,0);
        uint256 lastUnclaimedReward_ = rewards.lastUnclaimedReward(depositor, token, network); 
        console2.log("rewards length: %s", rewards.rewardsLength(token, network));
        console2.log("amount: %s", amount);
        console2.log("timestamp: %s", timestamp1);
        console2.log("lastUnclaimedReward_: %s", lastUnclaimedReward_);

     ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        console2.log("balance of depositor before: %s", hyper.balanceOf(depositor));

        // Claim rewards
        rewards.claimRewards(
            depositor,
           0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011, // HYPER
            abi.encode(network, type(uint256).max, bytes(""))
        );
        console2.log("balance of depositor after: %s", hyper.balanceOf(depositor));


    }
}
