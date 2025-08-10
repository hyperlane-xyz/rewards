// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import {IDefaultStakerRewards} from "src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";

contract DistributeRewardsStaging is Script {
    function _start() internal returns (address) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);
        return deployer;
    }

    function run() public {
        address deployer = _start();

        ERC20 hyper = ERC20(0xC10c27afcb915439C27cAe54F5F46Da48cd71190);
        hyper.approve(0x049B578496Fd092e2c0f3E537869fDBFD5Fef379, type(uint256).max);

        // 1. distribute rewards
        IDefaultStakerRewards rewards = IDefaultStakerRewards(0x049B578496Fd092e2c0f3E537869fDBFD5Fef379);
        uint48 timestamp = uint48(block.timestamp - 1);
        rewards.distributeRewards(
            deployer,
            0xC10c27afcb915439C27cAe54F5F46Da48cd71190, // HYPER
            1 ether,
            abi.encode(timestamp, 0, bytes(""), bytes(""))
        );
    }

    function claimRewards() public {
        address deployer = _start();

        IDefaultStakerRewards rewards = IDefaultStakerRewards(0x049B578496Fd092e2c0f3E537869fDBFD5Fef379);
        uint48 timestamp = uint48(block.timestamp - 1);
        rewards.claimRewards(
            0xa7ECcdb9Be08178f896c26b7BbD8C3D4E844d9Ba,
            0xC10c27afcb915439C27cAe54F5F46Da48cd71190, // HYPER
            abi.encode(timestamp, type(uint256).max, bytes(""), bytes(""))
        );
    }
}
