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

contract HypMinterTest is Test {
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

    // Symbiotic network addresses
    NetworkMiddlewareService networkMiddlewareService =
        NetworkMiddlewareService(0xD7dC9B366c027743D90761F71858BCa83C6899Ad);

    // Fork block number - using a recent block
    uint256 constant FORK_BLOCK_NUMBER = 23_291_197;

    function setUp() public {
        // Fork Ethereum mainnet - use fallback if ETH_RPC_URL not set
        vm.createSelectFork("mainnet", FORK_BLOCK_NUMBER);

        // Deploy the contract
        // Initialize with a timestamp in the past for testing
        uint256 firstTimestamp = block.timestamp - 31 days;
        // 2025-10-17 23:14:47 GMT
        uint256 mintAllowedTimestamp = 1_760_742_887;

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

        // Label addresses for better test output
        vm.label(address(HYPER), "HYPER");
        vm.label(address(REWARDS), "REWARDS");
        vm.label(SYMBIOTIC_NETWORK, "SYMBIOTIC_NETWORK");
        vm.label(address(hypMinter), "HypMinter");
        vm.label(address(accessManager), "accessManager");
        vm.label(multisigB, "multisigB");
    }

    function test_mintAndDistribute_SuccessfulDistribution() public {
        // Pre-requisite. Set the network middleware to be HypMinter
        vm.prank(SYMBIOTIC_NETWORK);
        networkMiddlewareService.setMiddleware(address(hypMinter));

        // Fast forward to after the start time (2025-10-17 23:14:47 GMT)
        vm.warp(hypMinter.mintAllowedTimestamp() + 1);

        // Give the AccessManager the `MINTER_ROLE` on HYPER contract
        // 1. Schedule a grantRole operation via the AccessManager
        vm.prank(multisigB);
        bytes memory data = abi.encodeCall(AccessControl.grantRole, (keccak256("MINTER_ROLE"), address(hypMinter)));
        accessManager.schedule(address(HYPER), data, 0);

        // 2. Execute the operation
        vm.prank(multisigB);
        skip(30 days);
        accessManager.execute(address(HYPER), data);

        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));

        // Expect Mint event to be emitted
        vm.expectEmit(true, true, true, true);
        emit HypMinter.Mint();
        // Expect Distribution event to be emitted with current operator bps
        vm.expectEmit(true, true, true, true);
        emit HypMinter.Distribution(OPERATOR_BPS);

        hypMinter.mintAndDistribute();
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());
    }

    function test_3_mints() public {
        test_mintAndDistribute_SuccessfulDistribution();
        skip(30 days);

        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mintAndDistribute();
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());

        skip(30 days);
        initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mintAndDistribute();
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());
    }

    function test_mintAndDistribute_CorrectAmountCalculations() public view {
        uint256 operatorAmount = (MINT_AMOUNT * OPERATOR_BPS) / MAX_BPS;
        uint256 stakingAmount = MINT_AMOUNT - operatorAmount;

        // Verify calculations
        assertEq(operatorAmount, hypMinter.getOperatorMintAmount());
        assertEq(stakingAmount, hypMinter.getStakingMintAmount());
        assertEq(operatorAmount + stakingAmount, MINT_AMOUNT);
    }

    function test_setOperatorRewardsBps() public {
        uint256 newBps = 1500; // 15%
        vm.prank(accessManagerAdmin);

        // Expect OperatorBpsSet event to be emitted
        vm.expectEmit(true, true, true, true);
        emit HypMinter.OperatorBpsSet(newBps);
        hypMinter.setOperatorRewardsBps(newBps);

        assertEq(hypMinter.operatorBps(), newBps);
    }

    function test_setOperatorRewardsManager() public {
        address newManager = makeAddr("newManager");

        vm.prank(accessManagerAdmin);
        // Expect OperatorRewardsManagerSet event to be emitted
        vm.expectEmit(true, true, true, true);
        emit HypMinter.OperatorRewardsManagerSet(newManager);
        hypMinter.setOperatorRewardsManager(newManager);

        assertEq(hypMinter.operatorRewardsManager(), newManager);
    }

    function test_amountCalculations() public {
        // Test the calculations are correct based on the contract logic
        uint256 operatorAmount = (MINT_AMOUNT * OPERATOR_BPS) / MAX_BPS;
        uint256 stakingAmount = MINT_AMOUNT - operatorAmount;

        // Verify the math
        assertEq(operatorAmount, hypMinter.getOperatorMintAmount());
        assertEq(stakingAmount, hypMinter.getStakingMintAmount());
        assertEq(operatorAmount + stakingAmount, MINT_AMOUNT);
    }

    // ========== Additional Simple Tests ==========

    function test_mintAndDistribute_RevertsBeforeStartTime() public {
        vm.warp(hypMinter.mintAllowedTimestamp() - 1);

        vm.expectRevert("HypMinter: Minting not started");
        hypMinter.mintAndDistribute();
    }

    function test_getOperatorMintAmount_WithDifferentBps() public {
        assertEq(hypMinter.operatorBps(), 1000);

        // Test with 5% (500 bps)
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(500);

        uint256 expected = (MINT_AMOUNT * 500) / MAX_BPS;
        assertEq(hypMinter.getOperatorMintAmount(), expected);
    }

    function test_getStakingMintAmount_WithDifferentBps() public {
        // Test with 5% operator (95% staking)
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(500);

        uint256 expected = MINT_AMOUNT - ((MINT_AMOUNT * 500) / MAX_BPS);
        assertEq(hypMinter.getStakingMintAmount(), expected);
    }

    function test_mintAmount_IsCorrect() public {
        // Verify the hardcoded mint amount
        assertEq(hypMinter.MINT_AMOUNT(), 666_667 ether);
    }

    function test_maxBps_IsCorrect() public {
        // Verify MAX_BPS represents 100%
        assertEq(hypMinter.MAX_BPS(), 10_000);
    }

    function test_setOperatorRewardsBps_WithZero() public {
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(0);

        assertEq(hypMinter.operatorBps(), 0);
        assertEq(hypMinter.getOperatorMintAmount(), 0);
        assertEq(hypMinter.getStakingMintAmount(), MINT_AMOUNT);
    }

    function test_setOperatorRewardsBps_WithMaxBps() public {
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(MAX_BPS);

        assertEq(hypMinter.operatorBps(), MAX_BPS);
        assertEq(hypMinter.getOperatorMintAmount(), MINT_AMOUNT);
        assertEq(hypMinter.getStakingMintAmount(), 0);
    }

    function test_amountCalculations_AlwaysAddUp() public {
        // Test that operator + staking always equals total mint
        uint256 operator = hypMinter.getOperatorMintAmount();
        uint256 staking = hypMinter.getStakingMintAmount();

        assertEq(operator + staking, MINT_AMOUNT);
        assertEq(operator + staking, hypMinter.MINT_AMOUNT());
    }

    function test_unauthorized_CannotCallRestrictedFunctions() public {
        address unauthorized = makeAddr("unauthorized");

        // Test operatorBps
        vm.prank(unauthorized);
        vm.expectRevert();
        hypMinter.setOperatorRewardsBps(1500);

        // Test operatorRewardsManager
        vm.prank(unauthorized);
        vm.expectRevert();
        hypMinter.setOperatorRewardsManager(makeAddr("newManager"));
    }

    function test_initialization_CannotReinitialize() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        hypMinter.initialize(block.timestamp, block.timestamp + 30 days, accessManager);
    }

    function test_hyper_HasCorrectApproval() public {
        // Verify HYPER has max approval for REWARDS contract
        uint256 allowance = HYPER.allowance(address(hypMinter), address(REWARDS));
        assertEq(allowance, type(uint256).max);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_operatorRewardsBps(
        uint256 bps
    ) public {
        // Only test valid bps values (0 to MAX_BPS = 10,000)
        vm.assume(bps <= MAX_BPS);

        // Set the operator rewards percentage
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(bps);

        // Verify the value was set correctly
        assertEq(hypMinter.operatorBps(), bps);

        // Calculate expected amounts
        uint256 expectedOperatorAmount = (MINT_AMOUNT * bps) / MAX_BPS;
        uint256 expectedStakingAmount = MINT_AMOUNT - expectedOperatorAmount;

        // Verify calculations are correct
        assertEq(hypMinter.getOperatorMintAmount(), expectedOperatorAmount);
        assertEq(hypMinter.getStakingMintAmount(), expectedStakingAmount);

        // Verify they always add up to the total mint amount
        assertEq(hypMinter.getOperatorMintAmount() + hypMinter.getStakingMintAmount(), MINT_AMOUNT);

        // Test edge cases within the fuzz
        if (bps == 0) {
            assertEq(hypMinter.getOperatorMintAmount(), 0);
            assertEq(hypMinter.getStakingMintAmount(), MINT_AMOUNT);
        } else if (bps == MAX_BPS) {
            assertEq(hypMinter.getOperatorMintAmount(), MINT_AMOUNT);
            assertEq(hypMinter.getStakingMintAmount(), 0);
        }
    }
}
