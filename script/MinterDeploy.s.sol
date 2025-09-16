// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {HypMinter, IERC20Mintable} from "../src/contracts/HypMinter.sol";
import {IDefaultStakerRewards} from "../src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IStakerRewards} from "../src/interfaces/stakerRewards/IStakerRewards.sol";
import {NetworkMiddlewareService} from "../lib/core/src/contracts/service/NetworkMiddlewareService.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MinterDeploy is Script, Test {
    HypMinter hypMinter;

    // Events from HypMinter contract
    event Mint();
    event Distribution(uint256 operatorRewardsBps);
    event OperatorBpsSet(uint256 bps);
    event OperatorRewardsManagerSet(address manager);

    // Reward contract addresses
    IERC20Mintable HYPER;
    IDefaultStakerRewards REWARDS;
    address SYMBIOTIC_NETWORK;

    // Constants from contract
    uint256 MINT_AMOUNT;
    uint256 MAX_BPS;
    uint256 OPERATOR_BPS;

    // Admin addresses
    AccessManager accessManager = AccessManager(0x3D079E977d644c914a344Dcb5Ba54dB243Cc4863);
    address accessManagerAdmin = 0xfA842f02439Af6d91d7D44525956F9E5e00e339f;
    address multisigB = 0xec2EdC01a2Fbade68dBcc80947F43a5B408cC3A0;
    TimelockController timelockController = TimelockController(payable(0xfA842f02439Af6d91d7D44525956F9E5e00e339f));

    // Symbiotic network addresses
    NetworkMiddlewareService networkMiddlewareService =
        NetworkMiddlewareService(0xD7dC9B366c027743D90761F71858BCa83C6899Ad);

    uint256 firstTimestamp;
    uint256 distributionDelay;
    // Fork block number - using a recent block
    uint256 constant FORK_BLOCK_NUMBER = 23_327_196;

    uint256 mintAllowedTimestamp = 1_760_446_800; // Tuesday, October 14, 2025 1:00:00 PM GMT-04:00 DST

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK_NUMBER);

        firstTimestamp = 1_752_448_487;

        // Read constants from implementation contract
        hypMinter = new HypMinter();
        HYPER = hypMinter.HYPER();
        REWARDS = hypMinter.REWARDS();
        SYMBIOTIC_NETWORK = hypMinter.SYMBIOTIC_NETWORK();
        MINT_AMOUNT = hypMinter.MINT_AMOUNT();
        MAX_BPS = hypMinter.MAX_BPS();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(hypMinter),
            address(this),
            abi.encodeCall(HypMinter.initialize, (firstTimestamp, mintAllowedTimestamp, accessManager))
        );
        // Set hypMinter to the proxy
        hypMinter = HypMinter(address(proxy));
        OPERATOR_BPS = hypMinter.operatorBps();
        distributionDelay = hypMinter.distributionDelay();

        // Label addresses for better test output
        vm.label(address(HYPER), "HYPER");
        vm.label(address(REWARDS), "REWARDS");
        vm.label(SYMBIOTIC_NETWORK, "SYMBIOTIC_NETWORK");
        vm.label(address(hypMinter), "HypMinter");
        vm.label(address(accessManager), "accessManager");
        vm.label(multisigB, "multisigB");
    }

    bytes setMiddlewareData;
    bytes networkScheduleData;
    bytes grantMinterRoleData;

    function schedule() public {
        setMiddlewareData = abi.encodeCall(NetworkMiddlewareService.setMiddleware, (address(hypMinter)));
        networkScheduleData = abi.encodeCall(
            TimelockController.schedule,
            (address(networkMiddlewareService), 0, setMiddlewareData, bytes32(0), bytes32(0), 0 days)
        );

        grantMinterRoleData = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), address(hypMinter)));

        // Multisig B can call schedule on network via accessManager
        vm.startBroadcast(address(multisigB));
        {
            accessManager.schedule(address(SYMBIOTIC_NETWORK), networkScheduleData, 0);
            accessManager.schedule(address(HYPER), grantMinterRoleData, 0);
        }
        vm.stopBroadcast();
    }

    function test_fullFlow() public {
        schedule();

        skip(30 days);
        vm.prank(multisigB);
        accessManager.execute(address(SYMBIOTIC_NETWORK), networkScheduleData);
        accessManager.execute(address(HYPER), grantMinterRoleData);

        vm.prank(makeAddr("alice"));
        TimelockController(payable(SYMBIOTIC_NETWORK)).execute({
            target: address(networkMiddlewareService),
            value: 0,
            payload: setMiddlewareData,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });

        assertEq(networkMiddlewareService.middleware(SYMBIOTIC_NETWORK), address(hypMinter));

        // Fast forward to after the start time
        vm.warp(hypMinter.mintAllowedTimestamp() + 1);

        
        // We send the already minted amount to the contract
        vm.prank(0x79271FB18A9Bfa8b8d987bc27A063Dc6F2912F52);
        HYPER.transfer(address(hypMinter), MINT_AMOUNT);

        // Three mints, yielding 4 epochs worth of rewards
        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mint();
        hypMinter.mint();
        hypMinter.mint();

        vm.expectRevert("HypMinter: Epoch not ready");
        hypMinter.mint();

        skip(7 days);
        uint256 distributionDeadline = 1761055200; // Tuesday, October 21, 2025 10:00:00 AM EST (1 week after minting is allowed)

        // Four distributions
        hypMinter.distributeRewards(firstTimestamp);
        hypMinter.distributeRewards(firstTimestamp + 30 days);
        hypMinter.distributeRewards(firstTimestamp + 60 days);
        hypMinter.distributeRewards(firstTimestamp + 90 days);
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount() * 4);
        console2.log("distribution timestamp: ", vm.getBlockTimestamp());
        assertGt(distributionDeadline, vm.getBlockTimestamp());

        // Expect revert when trying to distribute rewards again
        vm.expectRevert("HypMinter: Rewards already distributed");
        hypMinter.distributeRewards(firstTimestamp + 90 days);
    }

    function test_mintingThroughFoundation() public {
        address foundation = makeAddr("foundation");
        uint256 deployDate = 1_757_696_400;
        vm.warp(deployDate); // Sept 12th 2025

        uint256 startTimestamp = vm.getBlockTimestamp();
        console2.log("startTimestamp", startTimestamp);

        vm.prank(multisigB);
        bytes memory data = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), foundation));
        accessManager.schedule(address(HYPER), data, 0);

        // 2. Execute the operation
        vm.prank(multisigB);
        skip(30 days);
        accessManager.execute(address(HYPER), data);


        address dummyNetwork = 0xd96F4688873d00dc73B49F3fa2cC6925D7A64E8B;
        uint256 distributionDeadline = 1761055200; // Tuesday, October 21, 2025 10:00:00 AM EST (1 week after minting is allowed)
        uint256 initialBalanceNetwork= HYPER.balanceOf(dummyNetwork);

        // Mint  HYPER tokens to dummy network
        vm.prank(foundation);
        HYPER.mint(dummyNetwork, MINT_AMOUNT);
        assertEq(HYPER.balanceOf(dummyNetwork) - initialBalanceNetwork, MINT_AMOUNT);
        assertGt(distributionDeadline, vm.getBlockTimestamp());


        // Distribute rewards through dummy network
        uint256 initialBalanceREWARDS = HYPER.balanceOf(address(REWARDS));
        vm.startPrank(dummyNetwork);
        HYPER.approve(address(REWARDS), MINT_AMOUNT);
        REWARDS.distributeRewards(dummyNetwork, address(HYPER), MINT_AMOUNT, abi.encode(firstTimestamp, type(uint256).max, bytes(""), bytes("")));
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalanceREWARDS, MINT_AMOUNT);
        assertGt(distributionDeadline, vm.getBlockTimestamp());
        vm.stopPrank();
    }
}
