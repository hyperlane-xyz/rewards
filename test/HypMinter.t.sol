// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {HypMinter} from "../src/contracts/HypMinter.sol";
import {IDefaultStakerRewards} from "../src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IStakerRewards} from "../src/interfaces/stakerRewards/IStakerRewards.sol";
import {NetworkMiddlewareService} from "../lib/core/src/contracts/service/NetworkMiddlewareService.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function MINTER_ROLE() external view returns (bytes32);
}

interface IAccessManager {
    function grantRole(bytes32 role, address account, uint32 executionDelay) external;
    function hasRole(bytes32 role, address account) external view returns (bool, uint32);
}

contract HypMinterTest is Test {
    HypMinter hypMinter;

    // Mainnet addresses from the contract
    IERC20Mintable constant HYPER = IERC20Mintable(0x93A2Db22B7c736B341C32Ff666307F4a9ED910F5);
    IDefaultStakerRewards constant REWARDS = IDefaultStakerRewards(0x84852EB9acbE1869372f83ED853B185F6c2848Dc);
    address constant SYMBIOTIC_NETWORK = 0x59cf937Ea9FA9D7398223E3aA33d92F7f5f986A2;
    address constant OPERATOR_REWARDS_MANAGER = 0x2522d3797411Aff1d600f647F624713D53b6AA11;

    // Constants from contract
    uint256 constant MINT_AMOUNT = 666_667 ether;
    uint256 constant MAX_BPS = 10_000;
    uint256 constant OPERATOR_BPS = 1000; // 10%

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
        // TOOD: Deploy as a proxy
        hypMinter = new HypMinter();

        // Initialize with a timestamp in the past for testing
        uint256 firstTimestamp = block.timestamp - 31 days;
        hypMinter.initialize(firstTimestamp, accessManager);

        // Label addresses for better test output
        vm.label(address(HYPER), "HYPER");
        vm.label(address(REWARDS), "REWARDS");
        vm.label(SYMBIOTIC_NETWORK, "SYMBIOTIC_NETWORK");
        vm.label(OPERATOR_REWARDS_MANAGER, "OPERATOR_REWARDS_MANAGER");
        vm.label(address(hypMinter), "HypMinter");
        vm.label(address(accessManager), "accessManager");
        vm.label(multisigB, "multisigB");
    }

    function test_mintAndDistribute_SuccessfulDistribution() public {
        // Pre-requisite. Set the network middleware to be HypMinter
        vm.prank(SYMBIOTIC_NETWORK);
        networkMiddlewareService.setMiddleware(address(hypMinter));

        // Fast forward to after the start time (2025-10-17 23:14:47 GMT)
        vm.warp(1_760_742_887 + 1);

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
        hypMinter.setOperatorRewardsBps(newBps);

        assertEq(hypMinter.operatorBps(), newBps);
    }

    function test_setOperatorRewardsManager() public {
        address newManager = makeAddr("newManager");

        vm.prank(accessManagerAdmin);
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

    function test_constants() public {
        assertEq(address(hypMinter.HYPER()), address(HYPER));
        assertEq(address(hypMinter.REWARDS()), address(REWARDS));
        assertEq(hypMinter.SYMBIOTIC_NETWORK(), SYMBIOTIC_NETWORK);
        assertEq(hypMinter.MINT_AMOUNT(), MINT_AMOUNT);
        assertEq(hypMinter.MAX_BPS(), MAX_BPS);
    }

    // ========== Additional Simple Tests ==========

    function test_mintAndDistribute_RevertsBeforeStartTime() public {
        // Test before the hardcoded start time (2025-10-17 23:14:47 GMT)
        vm.warp(1_760_742_887 - 1);

        vm.expectRevert("Not started");
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
        hypMinter.initialize(block.timestamp, accessManager);
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
