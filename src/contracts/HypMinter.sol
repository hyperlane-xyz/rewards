// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {IDefaultStakerRewards} from "../interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";

/**
 * @title HypMinter
 * @notice Contract responsible for minting and distributing HYPER tokens to stakers and operators
 * @dev Implements a 30-day epoch system for token distribution with configurable operator rewards
 */
contract HypMinter is AccessManagedUpgradeable {
    /**
     * @notice Timestamp of the last minting operation
     * @dev Used to enforce 30-day epochs between minting operations
     */
    uint256 public lastRewardTimestamp;

    /// @notice Timestamp when minting is first allowed to begin
    uint256 public mintAllowedTimestamp;

    struct DistributionInfo {
        bool minted;
        bool distributed;
    }

    mapping(uint256 rewardTimestamp => DistributionInfo distributionInfo) public rewardDistributions;

    /// @notice Delay between mint time and reward timestamp passed to the rewards contract
    uint256 public distributionDelay;

    /**
     * @notice Total amount of HYPER tokens minted per epoch
     * @dev Fixed at 666,667 HYPER tokens per minting cycle
     */
    uint256 public constant MINT_AMOUNT = 666_667 * (10 ** 18);

    /// @notice The HYPER token contract
    IERC20Mintable public constant HYPER = IERC20Mintable(0x93A2Db22B7c736B341C32Ff666307F4a9ED910F5);

    /**
     * @notice The staker rewards distribution contract
     * @dev Contract responsible for distributing rewards to stakers
     */
    IDefaultStakerRewards public constant REWARDS = IDefaultStakerRewards(0x84852EB9acbE1869372f83ED853B185F6c2848Dc);

    /**
     * @notice The Symbiotic network address for reward distribution
     * @dev Network identifier used when distributing staker rewards
     */
    address public constant SYMBIOTIC_NETWORK = 0x59cf937Ea9FA9D7398223E3aA33d92F7f5f986A2;

    /**
     * @notice Address that receives operator rewards
     * @dev Should be the Foundation multisig address
     */
    address public operatorRewardsManager;
    /**
     * @notice Maximum basis points value (100%)
     * @dev Used for percentage calculations, where 10,000 = 100%
     */
    uint256 public constant MAX_BPS = 10_000;

    /**
     * @notice Basis points allocated to operator rewards
     * @dev Default is 1,000 basis points (10%). Can be modified by authorized accounts
     */
    uint256 public operatorBps;

    event Mint();
    event Distribution(uint256 operatorRewardsBps);
    event OperatorBpsSet(uint256 bps);
    event OperatorRewardsManagerSet(address manager);
    event DistributionDelaySet(uint256 distributionDelay);
    /**
     * @notice Constructor that disables initializers for the implementation contract
     * @dev Prevents the implementation contract from being initialized directly
     */

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the HypMinter contract
     * @param _firstMintTimestamp The initial timestamp for the first minting epoch
     * @param _mintAllowedTimestamp The timestamp when minting is first allowed to begin
     * @param _accessManager The access manager contract for role-based permissions
     * @dev Sets up the contract with initial timestamps, default operator settings, and approves HYPER tokens for rewards distribution
     */
    function initialize(
        uint256 _firstMintTimestamp,
        uint256 _mintAllowedTimestamp,
        AccessManager _accessManager
    ) external initializer {
        __AccessManaged_init(address(_accessManager));

        // Set minting timestamps
        lastRewardTimestamp = _firstMintTimestamp;
        rewardDistributions[_firstMintTimestamp].minted = true;
        mintAllowedTimestamp = _mintAllowedTimestamp;
        distributionDelay = 7 days;

        // Initialize operator rewards settings with default values
        operatorRewardsManager = 0x2522d3797411Aff1d600f647F624713D53b6AA11;
        operatorBps = 1000;

        // Approve maximum HYPER tokens for rewards distribution to avoid future approval calls
        HYPER.approve(address(REWARDS), type(uint256).max);
    }

    /**
     * @notice Mints HYPER tokens and distributes them to stakers and operators
     * @dev Can only be called after mintAllowedTimestamp and respects 30-day epochs
     */
    function mint() external {
        require(block.timestamp >= mintAllowedTimestamp, "HypMinter: Minting not started");

        // Calculate next epoch timestamp (30 days after last mint)
        uint256 newTimestamp = lastRewardTimestamp + 30 days;
        require(block.timestamp >= newTimestamp, "HypMinter: Epoch not ready");

        // Update the last mint timestamp for next epoch calculation
        rewardDistributions[newTimestamp].minted = true;
        lastRewardTimestamp = newTimestamp;

        // Mint the full amount to this contract
        HYPER.mint(address(this), MINT_AMOUNT);
        emit Mint();
    }

    function distributeRewards(
        uint256 rewardTimestamp
    ) external {
        // Check if the distribution is ready
        require(block.timestamp >= rewardTimestamp + distributionDelay, "HypMinter: Distribution not ready");

        // Check if timestamp is valid and not already distributed
        DistributionInfo memory distributionInfo = rewardDistributions[rewardTimestamp];
        require(distributionInfo.minted, "HypMinter: Rewards not minted");
        require(!distributionInfo.distributed, "HypMinter: Rewards already distributed");

        // Update the distribution info
        rewardDistributions[rewardTimestamp].distributed = true;

        // Distribute staking rewards
        REWARDS.distributeRewards({
            network: SYMBIOTIC_NETWORK,
            token: address(HYPER),
            amount: getStakingMintAmount(),
            data: abi.encode(rewardTimestamp, type(uint256).max, bytes(""), bytes(""))
        });

        // Distribute operator rewards
        HYPER.transfer(operatorRewardsManager, getOperatorMintAmount());
        emit Distribution(operatorBps);
    }

    function setDistributionDelay(
        uint256 _distributionDelay
    ) external restricted {
        require(_distributionDelay <= 7 days, "HypMinter: Distribution delay must be less than 7 days");
        distributionDelay = _distributionDelay;
        emit DistributionDelaySet(_distributionDelay);
    }

    /**
     * @notice Calculates the amount of tokens allocated for staking rewards
     * @return The amount of HYPER tokens for stakers (total mint minus operator rewards)
     * @dev Subtracts operator rewards from the total mint amount
     */
    function getStakingMintAmount() public view returns (uint256) {
        // Subtract operator rewards to get staking rewards
        return MINT_AMOUNT - getOperatorMintAmount();
    }

    /**
     * @notice Calculates the amount of tokens allocated for operator rewards
     * @return mintAmount The amount of HYPER tokens for operators based on operatorBps
     * @dev Applies the operator percentage to the total mint amount
     */
    function getOperatorMintAmount() public view returns (uint256) {
        return (MINT_AMOUNT * operatorBps) / MAX_BPS;
    }

    /**
     * @notice Sets the percentage of rewards allocated to operators
     * @param bps The new operator rewards percentage in basis points (e.g., 1000 = 10%)
     * @dev Can only be called by authorized accounts (AW Multisig) with 30-day delay
     * @dev Must be between 0 and MAX_BPS (10,000) inclusive
     */
    function setOperatorRewardsBps(
        uint256 bps
    ) external restricted {
        require(bps <= MAX_BPS, "HypMinter: Invalid BPS");
        operatorBps = bps;
        emit OperatorBpsSet(bps);
    }

    /**
     * @notice Updates the address that receives operator rewards
     * @param _manager The new operator rewards manager address
     * @dev Can only be called by authorized accounts (AW Multisig) with 30-day delay
     * @dev The new manager address will receive operator rewards from subsequent mints
     */
    function setOperatorRewardsManager(
        address _manager
    ) external restricted {
        require(_manager != address(0), "HypMinter: Invalid manager address");
        operatorRewardsManager = _manager;
        emit OperatorRewardsManagerSet(_manager);
    }
}
