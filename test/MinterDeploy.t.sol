// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {HypMinter, IERC20Mintable} from "../src/contracts/HypMinter.sol";
import {IDefaultStakerRewards} from "../src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IStakerRewards} from "../src/interfaces/stakerRewards/IStakerRewards.sol";
import {NetworkMiddlewareService} from "../lib/core/src/contracts/service/NetworkMiddlewareService.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MinterDeployTest is Test {
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

    function test_fullFlow() public {
        uint256 deployDate = 1_757_696_400;
        vm.warp(deployDate); // Sept 12th 2025

        uint256 startTimestamp = vm.getBlockTimestamp();
        console2.log("startTimestamp", startTimestamp);
        uint256 mintDeadline = mintAllowedTimestamp + 1 days; // Wednesday, October 15, 2025 1:00:00 PM GMT
        assertGt(mintDeadline, hypMinter.mintAllowedTimestamp());

        // Pre-requisite. Set the network middleware to be HypMinter via AccessManager
        TimelockController _network = TimelockController(payable(SYMBIOTIC_NETWORK));

        bytes memory setMiddlewareData = abi.encodeCall(NetworkMiddlewareService.setMiddleware, (address(hypMinter)));
        bytes memory networkScheduleData = abi.encodeCall(
            TimelockController.schedule,
            (address(networkMiddlewareService), 0, setMiddlewareData, bytes32(0), bytes32(0), 0 days)
        );
        bytes memory accessManagerScheduleData = abi.encodeCall(
            AccessManager.schedule, (SYMBIOTIC_NETWORK, networkScheduleData, uint48(vm.getBlockTimestamp()))
        );

        // Multisig B can call schedule on network via accessManager
        vm.prank(multisigB);
        accessManager.schedule(address(_network), networkScheduleData, uint48(vm.getBlockTimestamp()) + 7 days);
        skip(7 days);
        vm.prank(multisigB);
        accessManager.execute(address(_network), networkScheduleData);

        vm.prank(makeAddr("alice"));
        _network.execute({
            target: address(networkMiddlewareService),
            value: 0,
            payload: setMiddlewareData,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });

        assertEq(networkMiddlewareService.middleware(SYMBIOTIC_NETWORK), address(hypMinter));

        // Give HypMinter the `MINTER_ROLE` on HYPER contract through the AccessManager
        // 1. Schedule a grantRole operation via the AccessManager
        vm.warp(startTimestamp); // Do this the same day as the middleware operations
        vm.prank(multisigB);
        bytes memory data = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), address(hypMinter)));
        accessManager.schedule(address(HYPER), data, 0);

        // 2. Execute the operation
        vm.prank(multisigB);
        skip(30 days);
        accessManager.execute(address(HYPER), data);

        console2.log("HypMinter gets MINTER_ROLE at: ", vm.getBlockTimestamp());
        assertGt(mintDeadline, vm.getBlockTimestamp());

        // Fast forward to after the start time
        vm.warp(Math.max(vm.getBlockTimestamp(), hypMinter.mintAllowedTimestamp() + 1));

        // Three mints
        deal(address(HYPER), address(hypMinter), MINT_AMOUNT); // We send the already minted amount to the contract
        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mint();
        hypMinter.mint();
        hypMinter.mint();

        skip(7 days);
        uint256 distributionDeadline = 1_761_051_600 + 5 hours; // Tuesday, October 21, 2025 6:00:00 PM GMT (1 week and 5 hours after minting is allowed)

        // Four distributions
        hypMinter.distributeRewards(firstTimestamp);
        hypMinter.distributeRewards(firstTimestamp + 30 days);
        hypMinter.distributeRewards(firstTimestamp + 60 days);
        hypMinter.distributeRewards(firstTimestamp + 90 days);
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount() * 4);
        console2.log("distribution timestamp: ", vm.getBlockTimestamp());
        assertGt(distributionDeadline, vm.getBlockTimestamp());
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

        uint256 distributionDeadline = 1_761_051_600 + 5 hours; // Tuesday, October 21, 2025 6:00:00 PM GMT (1 week and 5 hours after minting is allowed)
        uint256 initialBalance = HYPER.balanceOf(address(foundation));

        vm.prank(foundation);
        HYPER.mint(address(foundation), MINT_AMOUNT);
        assertEq(HYPER.balanceOf(address(foundation)) - initialBalance, MINT_AMOUNT);
        assertGt(distributionDeadline, vm.getBlockTimestamp());
    }
}
