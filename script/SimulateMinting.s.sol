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

contract SimulateMinting is Script, Test {
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

    address minter = vm.envAddress("MINTER");

    uint256 firstTimestamp;
    uint256 distributionDelay;

    function setUp() public {
        hypMinter = HypMinter(minter);

        assertGt(minter.code.length, 0, "Minter contract not deployed");

        HYPER = hypMinter.HYPER();
        REWARDS = hypMinter.REWARDS();
        SYMBIOTIC_NETWORK = hypMinter.SYMBIOTIC_NETWORK();
        MINT_AMOUNT = hypMinter.MINT_AMOUNT();
        MAX_BPS = hypMinter.MAX_BPS();
        OPERATOR_BPS = hypMinter.operatorBps();
        distributionDelay = hypMinter.distributionDelay();
        firstTimestamp = hypMinter.lastRewardTimestamp();
    }

    function run() public {
        vm.startBroadcast(address(multisigB));
        uint48 when = uint48(block.timestamp + 30 days);
        schedule(when);
        skip(30 days);
        execute();
        vm.stopBroadcast();

        uint256 snapshotId = vm.snapshot();
        test_minter();
        vm.revertTo(snapshotId);
        test_mintingThroughFoundation();
    }

    bytes setMiddlewareData;
    bytes networkScheduleData;
    bytes grantMinterRoleData;
    bytes grantFoundationRoleData;

    function schedule(uint48 when) public {
        setMiddlewareData = abi.encodeCall(NetworkMiddlewareService.setMiddleware, (address(hypMinter)));
        networkScheduleData = abi.encodeCall(
            TimelockController.schedule,
            (address(networkMiddlewareService), 0, setMiddlewareData, bytes32(0), bytes32(0), 0 days)
        );

        grantMinterRoleData = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), address(hypMinter)));
        grantFoundationRoleData = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), address(multisigB)));

        accessManager.schedule(address(SYMBIOTIC_NETWORK), networkScheduleData, when);
        accessManager.schedule(address(HYPER), grantMinterRoleData, when);
        accessManager.schedule(address(HYPER), grantFoundationRoleData, when);
    }

    function execute() public {
        accessManager.execute(address(SYMBIOTIC_NETWORK), networkScheduleData);
        accessManager.execute(address(HYPER), grantMinterRoleData);
        accessManager.execute(address(HYPER), grantFoundationRoleData);
    }

    function test_minter() public {
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
        vm.warp(hypMinter.mintAllowedTimestamp());

        // We send the already minted amount to the contract
        assertEq(HYPER.balanceOf(address(hypMinter)), 0);
        vm.startPrank(0x79271FB18A9Bfa8b8d987bc27A063Dc6F2912F52);
        HYPER.transfer(address(hypMinter), hypMinter.getStakingMintAmount());
        HYPER.transfer(address(multisigB), hypMinter.getOperatorMintAmount());
        vm.stopPrank();

        // Three mints, yielding 4 epochs worth of rewards
        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mint();
        hypMinter.mint();
        hypMinter.mint();

        vm.expectRevert("HypMinter: Epoch not ready");
        hypMinter.mint();
        assertEq(HYPER.balanceOf(address(hypMinter)), hypMinter.getStakingMintAmount() * 4);

        vm.warp(hypMinter.distributionAllowedTimestamp());

        // Four distributions
        hypMinter.distributeRewards(firstTimestamp);
        hypMinter.distributeRewards(firstTimestamp + 30 days);
        hypMinter.distributeRewards(firstTimestamp + 60 days);
        hypMinter.distributeRewards(firstTimestamp + 90 days);

        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount() * 4);
        assertEq(HYPER.balanceOf(address(hypMinter)), 0);

        // Expect revert when trying to distribute rewards again
        vm.expectRevert("HypMinter: Rewards must be available for distribution");
        hypMinter.distributeRewards(firstTimestamp + 90 days);

        vm.expectRevert("HypMinter: Distribution not ready");
        hypMinter.distributeRewards(firstTimestamp + 120 days);
    }

    function test_mintingThroughFoundation() public {
        address dummyNetwork = 0xd96F4688873d00dc73B49F3fa2cC6925D7A64E8B;
        uint256 distributionDeadline = 1761055200; // Tuesday, October 21, 2025 10:00:00 AM EST (1 week after minting is allowed)
        uint256 initialBalanceNetwork= HYPER.balanceOf(dummyNetwork);

        // Mint  HYPER tokens to dummy network
        vm.prank(multisigB);
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
