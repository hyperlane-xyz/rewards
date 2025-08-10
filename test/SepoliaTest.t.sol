// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDefaultStakerRewards} from "src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {console2} from "forge-std/console2.sol";
import {NetworkRegistry} from "lib/core/src/contracts/NetworkRegistry.sol";
import {NetworkMiddlewareService} from "lib/core/src/contracts/service/NetworkMiddlewareService.sol";
import {IVaultTokenized} from "lib/core/src/interfaces/vault/IVaultTokenized.sol";

contract DistributeRewardsStaging is Test {
    function setUp() public {
        vm.createSelectFork("sepolia");
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


    function testDistributeRewards() public {
        address deployer = _getNetwork();
        vm.startPrank(deployer);

        _setupNetwork();
        _registerMiddleware();

        IDefaultStakerRewards rewards = IDefaultStakerRewards(0xe0bf535F776d900D499407623C03bACe81334127);
        ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        hyper.approve(address(rewards), type(uint256).max);

        // 1. distribute rewards
        uint48 timestamp = uint48(block.timestamp - 1); // Distributions must be for timestamp in the past
        rewards.distributeRewards(
            deployer,
            address(hyper), // HYPER
            0.001 ether,
            abi.encode(timestamp, 0, bytes(""), bytes(""))
        );
        vm.stopPrank();
    }

    function testDeposit() public {
        address depositor = makeAddr("depositor");
        address deployer = _getNetwork();

        ERC20 hyper = ERC20(0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011);
        vm.prank(deployer);   
        hyper.transfer(depositor, 0.001 ether);

        IVaultTokenized vault = IVaultTokenized(0xF56179944D867469612D138c74F1dE979D3faC72);
        vm.startPrank(depositor);
        hyper.approve(address(vault), type(uint256).max);

        // 1. deposit
        vault.deposit(depositor, 0.001 ether);
        assertEq(vault.activeBalanceOf(depositor), 0.001 ether);

        vm.stopPrank();
    }

    function testClaimRewards() public {
        testDeposit();
        vm.warp(block.timestamp + 1 days);
        testDistributeRewards();

        address depositor = makeAddr("depositor");
        vm.startPrank(depositor);


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

        // Claim rewards
        rewards.claimRewards(
            depositor,
           0x1e111DF35aD11B3d18e5b5E9A7fd4Ed8dc841011, // HYPER
            abi.encode(network, type(uint256).max, bytes(""))
        );
        vm.stopPrank();
    }
}