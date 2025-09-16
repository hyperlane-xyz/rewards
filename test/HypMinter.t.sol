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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract HypMinterTest is Test {
    HypMinter hypMinter;

    // Events from HypMinter contract
    event Mint();
    event Distribution(uint256 operatorRewardsBps);
    event OperatorBpsSet(uint256 bps);
    event OperatorRewardsManagerSet(address manager);
    event DistributionDelaySet(uint256 distributionDelay);

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
    address multisigA = 0x562Dfaac27A84be6C96273F5c9594DA1681C0DA7;

    // Symbiotic network addresses
    NetworkMiddlewareService networkMiddlewareService =
        NetworkMiddlewareService(0xD7dC9B366c027743D90761F71858BCa83C6899Ad);

    uint256 firstTimestamp;
    uint256 distributionDelay;

    bytes constant DISTRIBUTE_REWARDS_ERROR = "HypMinter: Rewards must be available for distribution";
    // Fork block number - using a recent block
    uint256 constant FORK_BLOCK_NUMBER = 23_327_196;

    function setUp() public {
        // Fork Ethereum mainnet - use fallback if ETH_RPC_URL not set
        vm.createSelectFork("mainnet", FORK_BLOCK_NUMBER);

        // Deploy the contract
        // Initialize with a timestamp in the past for testing
        firstTimestamp = 1_752_448_487;
        // 2025-10-17 23:14:47 GMT
        uint256 mintAllowedTimestamp = 1_760_742_887;
        uint256 distributionAllowedTimestamp = 1_761_141_600;

        // Read constants from implementation contract
        hypMinter = new HypMinter(7 days);
        HYPER = hypMinter.HYPER();
        REWARDS = hypMinter.REWARDS();
        SYMBIOTIC_NETWORK = hypMinter.SYMBIOTIC_NETWORK();
        MINT_AMOUNT = hypMinter.MINT_AMOUNT();
        MAX_BPS = hypMinter.MAX_BPS();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(hypMinter),
            address(this),
            abi.encodeCall(
                HypMinter.initialize,
                (accessManager, firstTimestamp, distributionAllowedTimestamp - 7 days, distributionAllowedTimestamp, 7 days, multisigA)
            )
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

    function _setMiddleware() internal {
        if (networkMiddlewareService.middleware(SYMBIOTIC_NETWORK) != address(hypMinter)) {
            vm.prank(SYMBIOTIC_NETWORK);
            networkMiddlewareService.setMiddleware(address(hypMinter));
        }
    }

    function test_mintAndDistribute_SuccessfulDistribution() public {
        // Pre-requisite. Set the network middleware to be HypMinter
        _setMiddleware();

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

        // Fast forward to after the start time
        vm.warp(Math.max(vm.getBlockTimestamp(), hypMinter.mintAllowedTimestamp() + 1));
        uint256 initialOperatorBalance = HYPER.balanceOf(hypMinter.operatorRewardsManager());

        // Expect Mint event to be emitted
        vm.expectEmit(true, true, true, true);
        emit HypMinter.Mint();
        hypMinter.mint();
        assertEq(
            HYPER.balanceOf(hypMinter.operatorRewardsManager()) - initialOperatorBalance,
            hypMinter.getOperatorMintAmount()
        );

        skip(hypMinter.distributionDelay());

        // Expect Distribution event to be emitted with current operator bps
        vm.expectEmit(true, true, true, true);
        emit HypMinter.Distribution(hypMinter.operatorBps());
        hypMinter.distributeRewards(firstTimestamp + 30 days);
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());
    }

    function test_3_mints() public {
        test_mintAndDistribute_SuccessfulDistribution();
        skip(30 days);

        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mint();
        skip(hypMinter.distributionDelay());
        hypMinter.distributeRewards(firstTimestamp + 30 days * 2);
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());

        skip(30 days);
        initialBalance = HYPER.balanceOf(address(REWARDS));
        hypMinter.mint();

        skip(hypMinter.distributionDelay());
        hypMinter.distributeRewards(firstTimestamp + 30 days * 3);
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());
    }

    function test_one_epoch_minted() public {
        // We send the mint amount directly to the contract
        deal(address(HYPER), address(hypMinter), MINT_AMOUNT);

        vm.warp(hypMinter.mintAllowedTimestamp() + hypMinter.distributionDelay() + 1);

        // We distribute the rewards for the first epoch
        uint256 initialBalance = HYPER.balanceOf(address(REWARDS));
        _setMiddleware();
        hypMinter.distributeRewards(firstTimestamp);

        // We expect the staking rewards to be distributed
        assertEq(HYPER.balanceOf(address(REWARDS)) - initialBalance, hypMinter.getStakingMintAmount());

        test_3_mints();
    }

    function test_mintAndDistribute_CorrectAmountCalculations() public view {
        uint256 operatorAmount = (MINT_AMOUNT * OPERATOR_BPS) / MAX_BPS;
        uint256 stakingAmount = MINT_AMOUNT - operatorAmount;

        // Verify calculations
        assertEq(operatorAmount, hypMinter.getOperatorMintAmount());
        assertEq(stakingAmount, hypMinter.getStakingMintAmount());
        assertEq(operatorAmount + stakingAmount, MINT_AMOUNT);
    }

    function test_cannotDistributeTwice() public {
        test_mintAndDistribute_SuccessfulDistribution();

        // Try to distribute the same epoch again
        vm.expectRevert(DISTRIBUTE_REWARDS_ERROR);
        hypMinter.distributeRewards(firstTimestamp + 30 days);
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

    function test_mint_RevertsBeforeStartTime() public {
        vm.warp(hypMinter.mintAllowedTimestamp() - 1);

        vm.expectRevert("HypMinter: Minting not started");
        hypMinter.mint();
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
        hypMinter.initialize(accessManager, block.timestamp, block.timestamp, block.timestamp, 6 days, multisigA);
    }

    function test_hyper_HasCorrectApproval() public {
        // Verify HYPER has max approval for REWARDS contract
        uint256 allowance = HYPER.allowance(address(hypMinter), address(REWARDS));
        assertEq(allowance, type(uint256).max);
    }

    // ========== Distribution Delay Tests ==========

    function test_setDistributionDelay_Success() public {
        uint256 newDelay = 3 days;

        vm.prank(accessManagerAdmin);
        // Expect DistributionDelaySet event to be emitted
        vm.expectEmit(true, true, true, true);
        emit DistributionDelaySet(newDelay);
        hypMinter.setDistributionDelay(newDelay);

        assertEq(hypMinter.distributionDelay(), newDelay);
    }

    function test_setDistributionDelay_MaxDelay() public {
        uint256 newDelay = hypMinter.distributionDelayMaximum();

        vm.prank(accessManagerAdmin);
        vm.expectEmit(true, true, true, true);
        emit DistributionDelaySet(newDelay);
        hypMinter.setDistributionDelay(newDelay);

        assertEq(hypMinter.distributionDelay(), newDelay);
    }

    function test_setDistributionDelay_RevertsWhenTooLarge() public {
        uint256 invalidDelay = hypMinter.distributionDelayMaximum() + 1;

        vm.prank(accessManagerAdmin);
        vm.expectRevert("HypMinter: Distribution delay too large");
        hypMinter.setDistributionDelay(invalidDelay);
    }

    function test_setDistributionDelay_RevertsWhenUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        uint256 newDelay = 1 days;

        vm.prank(unauthorized);
        vm.expectRevert();
        hypMinter.setDistributionDelay(newDelay);
    }

    // ========== Misc Tests =========
    function test_setOperatorManager_AffectsNextMint() public {
        test_mintAndDistribute_SuccessfulDistribution();

        // Change operator manager
        address newManager = makeAddr("newOperatorManager");
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsManager(newManager);

        uint256 initialBalance = HYPER.balanceOf(newManager);

        // Next mint should go to new manager
        skip(30 days);
        hypMinter.mint();

        uint256 finalBalance = HYPER.balanceOf(newManager);
        uint256 expectedIncrease = hypMinter.getOperatorMintAmount();

        assertEq(finalBalance - initialBalance, expectedIncrease);
    }

    function test_rewardDistributions_StateTracking() public {
        uint256 epochTimestamp = firstTimestamp + 30 days;

        // Before mint - should be empty
        HypMinter.DistributionStatus distributionStatus = hypMinter.rewardDistributions(epochTimestamp);
        assertTrue(distributionStatus == HypMinter.DistributionStatus.NOT_MINTED);

        // After setup but before our mint
        test_mintAndDistribute_SuccessfulDistribution();

        // Check first epoch state
        distributionStatus = hypMinter.rewardDistributions(epochTimestamp);
        assertTrue(distributionStatus == HypMinter.DistributionStatus.DISTRIBUTED);

        // Mint next epoch
        skip(30 days);
        hypMinter.mint();

        uint256 nextEpochTimestamp = epochTimestamp + 30 days;
        distributionStatus = hypMinter.rewardDistributions(nextEpochTimestamp);
        assertTrue(distributionStatus == HypMinter.DistributionStatus.MINTED);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_operatorRewardsBps(
        uint256 bps
    ) public {
        // Only test valid bps values [0, MAX_BPS = 10,000)
        vm.assume(bps < MAX_BPS);

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

    function testFuzz_setDistributionDelay(
        uint256 delay
    ) public {
        // Only test valid delay values (0 to 7 days)
        vm.assume(delay <= 7 days);

        // Set the distribution delay
        vm.prank(accessManagerAdmin);
        hypMinter.setDistributionDelay(delay);

        // Verify the value was set correctly
        assertEq(hypMinter.distributionDelay(), delay);
    }

    function testFuzz_setDistributionDelay_RevertsWhenTooLarge(
        uint256 delay
    ) public {
        // Test values larger than distributionDelayMaximum
        vm.assume(delay > 7 days && delay < type(uint256).max / 2); // Avoid overflow

        vm.prank(accessManagerAdmin);
        vm.expectRevert("HypMinter: Distribution delay too large");
        hypMinter.setDistributionDelay(delay);
    }

    // ========== Advanced Fuzz Tests ==========

    function testFuzz_mint_DistributeWorkflow(uint256 operatorBps, uint256 delayDays) public {
        // Bound inputs to valid ranges
        operatorBps = bound(operatorBps, 0, MAX_BPS - 1);
        delayDays = bound(delayDays, 0, 7);
        uint256 delay = delayDays * 1 days;

        // Set up with random parameters
        vm.prank(accessManagerAdmin);
        hypMinter.setOperatorRewardsBps(operatorBps);
        vm.prank(accessManagerAdmin);
        hypMinter.setDistributionDelay(delay);

        // Set up initial successful distribution
        test_mintAndDistribute_SuccessfulDistribution();

        address operatorManager = hypMinter.operatorRewardsManager();
        uint256 operatorInitialBalance = HYPER.balanceOf(operatorManager);
        uint256 rewardsInitialBalance = HYPER.balanceOf(address(REWARDS));

        // Next epoch
        skip(30 days);
        uint256 epochTimestamp = firstTimestamp + 60 days;
        hypMinter.mint();

        // Verify operator got their share immediately
        uint256 expectedOperatorAmount = (MINT_AMOUNT * operatorBps) / MAX_BPS;
        assertEq(HYPER.balanceOf(operatorManager) - operatorInitialBalance, expectedOperatorAmount);

        // Distribute
        vm.warp(Math.max(vm.getBlockTimestamp(), epochTimestamp + delay));
        hypMinter.distributeRewards(epochTimestamp);

        // Verify stakers got their share
        uint256 expectedStakingAmount = MINT_AMOUNT - expectedOperatorAmount;
        assertEq(HYPER.balanceOf(address(REWARDS)) - rewardsInitialBalance, expectedStakingAmount);

        // Verify total amounts add up
        assertEq(expectedOperatorAmount + expectedStakingAmount, MINT_AMOUNT);
    }

    function testFuzz_multipleEpochs_ConsistentState(
        uint8 numEpochs
    ) public {
        // Bound to reasonable number of epochs
        numEpochs = uint8(bound(numEpochs, 1, 10));

        test_mintAndDistribute_SuccessfulDistribution();

        uint256 totalMinted = MINT_AMOUNT; // First mint from setup
        uint256 currentTimestamp = firstTimestamp + 30 days;

        for (uint256 i = 0; i < numEpochs; i++) {
            skip(30 days);
            currentTimestamp += 30 days;

            // Mint
            hypMinter.mint();
            totalMinted += MINT_AMOUNT;

            // Verify state
            HypMinter.DistributionStatus distributionStatus = hypMinter.rewardDistributions(currentTimestamp);
            assertTrue(distributionStatus == HypMinter.DistributionStatus.MINTED);

            // Distribute
            skip(distributionDelay);
            hypMinter.distributeRewards(currentTimestamp);

            // Verify distributed
            distributionStatus = hypMinter.rewardDistributions(currentTimestamp);
            assertTrue(distributionStatus == HypMinter.DistributionStatus.DISTRIBUTED);
        }

        // Verify lastRewardTimestamp is correct
        assertEq(hypMinter.lastRewardTimestamp(), currentTimestamp);
    }

    // ========== Invariant Tests ==========

    function test_invariant_totalSupplyIncreasesCorrectly() public {
        uint256 initialSupply = HYPER.totalSupply();

        test_mintAndDistribute_SuccessfulDistribution();

        uint256 afterFirstMint = HYPER.totalSupply();
        assertEq(afterFirstMint - initialSupply, MINT_AMOUNT);

        // Multiple mints
        for (uint256 i = 0; i < 5; i++) {
            skip(30 days);
            hypMinter.mint();
        }

        uint256 finalSupply = HYPER.totalSupply();
        assertEq(finalSupply - initialSupply, MINT_AMOUNT * 6); // 1 + 5 mints
    }

    function test_invariant_operatorPlusStakingEqualsTotal() public {
        // Test invariant across different BPS values
        uint256[] memory bpsValues = new uint256[](5);
        bpsValues[0] = 0;
        bpsValues[1] = 500; // 5%
        bpsValues[2] = 1000; // 10%
        bpsValues[3] = 5000; // 50%
        bpsValues[4] = 10_000 - 1; // 100%

        for (uint256 i = 0; i < bpsValues.length; i++) {
            vm.prank(accessManagerAdmin);
            hypMinter.setOperatorRewardsBps(bpsValues[i]);

            uint256 operatorAmount = hypMinter.getOperatorMintAmount();
            uint256 stakingAmount = hypMinter.getStakingMintAmount();

            // Invariant: operator + staking = total
            assertEq(operatorAmount + stakingAmount, MINT_AMOUNT);

            // Verify calculations
            assertEq(operatorAmount, (MINT_AMOUNT * bpsValues[i]) / MAX_BPS);
            assertEq(stakingAmount, MINT_AMOUNT - operatorAmount);
        }
    }

    // ========== Gas Optimization Tests ==========

    function test_gas_multipleOperations() public {
        test_mintAndDistribute_SuccessfulDistribution();

        // Measure gas for subsequent operations
        uint256 gasBefore = gasleft();

        skip(30 days);
        hypMinter.mint();

        uint256 gasAfterMint = gasleft();
        uint256 mintGas = gasBefore - gasAfterMint;

        skip(distributionDelay);
        hypMinter.distributeRewards(firstTimestamp + 60 days);

        uint256 gasAfterDistribute = gasleft();
        uint256 distributeGas = gasAfterMint - gasAfterDistribute;

        // Log gas usage for analysis
        console2.log("Mint gas used:", mintGas);
        console2.log("Distribute gas used:", distributeGas);

        // Basic assertions that operations didn't use excessive gas
        assertTrue(mintGas < 500_000, "Mint used too much gas");
        assertTrue(distributeGas < 500_000, "Distribute used too much gas");
    }
}
