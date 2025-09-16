// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {IDefaultStakerRewards} from "../interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IVaultTokenized} from "../../lib/core/src/interfaces/vault/IVaultTokenized.sol";
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

    /**
     * @notice Information about a reward distribution for a specific timestamp
     * @param mintTimestamp Timestamp when the rewards were minted for this epoch
     * @param distributed Whether the rewards have been distributed to stakers
     */
    /**
     * @notice Enumeration representing the distribution status of rewards for an epoch
     * @param NOT_MINTED Rewards have not been minted for this epoch yet
     * @param MINTED Rewards have been minted but not yet distributed
     * @param DISTRIBUTED Rewards have been minted and distributed to stakers
     */
    enum DistributionStatus {
        NOT_MINTED,
        MINTED,
        DISTRIBUTED
    }

    /**
     * @notice Mapping of reward timestamps to their distribution information
     * @dev Tracks minting and distribution status for each epoch
     */
    mapping(uint256 rewardTimestamp => DistributionStatus distributionStatus) public rewardDistributions;

    /**
     * @notice Delay between reward timestamp and distribution time
     * @dev This is the minimum time that must pass between a reward timestamp and when rewards can be distributed
     */
    uint256 public distributionDelay;

    /**
     * @notice Maximum delay between reward timestamp and distribution time
     * @dev Upper bound for distributionDelay to prevent excessively long delays
     */
    uint256 public immutable distributionDelayMaximum;

    /**
     * @notice Timestamp when distribution is allowed to begin
     * @dev Used to prevent distributions before a certain time, even if the distribution delay has passed
     */
    uint256 public distributionAllowedTimestamp;

    /**
     * @notice Total amount of HYPER tokens minted per epoch
     * @dev Fixed at 666,667 HYPER tokens per minting cycle
     */
    uint256 public constant MINT_AMOUNT = 666_667 * (10 ** 18);

    /// @notice The HYPER token contract
    IERC20Mintable public constant HYPER = IERC20Mintable(0x93A2Db22B7c736B341C32Ff666307F4a9ED910F5);

    /// @notice The staked HYPER token contract. This is a symbiotic vault.
    IVaultTokenized public constant STAKED_HYPER = IVaultTokenized(0xE1F23869776c82f691d9Cb34597Ab1830Fb0De58);

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

    /**
     * @notice Emitted when HYPER tokens are minted for an epoch
     * @dev Indicates successful minting of MINT_AMOUNT tokens to the contract
     */
    event Mint();

    /**
     * @notice Emitted when rewards are distributed to stakers
     * @param operatorRewardsBps The percentage of rewards allocated to operators in basis points
     */
    event Distribution(uint256 operatorRewardsBps);

    /**
     * @notice Emitted when the operator rewards percentage is updated
     * @param bps The new operator rewards percentage in basis points (e.g., 1000 = 10%)
     */
    event OperatorBpsSet(uint256 bps);

    /**
     * @notice Emitted when the operator rewards manager address is updated
     * @param manager The new address that will receive operator rewards
     */
    event OperatorRewardsManagerSet(address manager);

    /**
     * @notice Emitted when the distribution delay is updated
     * @param distributionDelay The new delay between reward timestamp and distribution in seconds
     */
    event DistributionDelaySet(uint256 distributionDelay);
    /**
     * @notice Constructor that sets the maximum distribution delay and disables initializers
     * @param _distributionDelayMaximum The maximum allowed delay between minting and distribution
     * @dev Prevents the implementation contract from being initialized directly
     */
    constructor(
        uint256 _distributionDelayMaximum
    ) {
        distributionDelayMaximum = _distributionDelayMaximum;
        _disableInitializers();
    }

    /**
     * @notice Initializes the HypMinter contract
     * @param _accessManager The access manager contract for role-based permissions
     * @param _firstRewardTimestamp The initial timestamp for the first minting epoch
     * @param _mintAllowedTimestamp The timestamp when minting is first allowed to begin
     * @param _distributionAllowedTimestamp The timestamp when distribution is first allowed to begin
     * @param _distributionDelay The delay between reward timestamp and when rewards can be distributed
     * @param _operatorRewardsManager The address that will receive operator rewards
     * @dev Sets up the contract with initial timestamps, default operator settings, and approves HYPER tokens for rewards distribution
     */
    function initialize(
        AccessManager _accessManager,
        uint256 _firstRewardTimestamp,
        uint256 _mintAllowedTimestamp,
        uint256 _distributionAllowedTimestamp,
        uint256 _distributionDelay,
        address _operatorRewardsManager
    ) external initializer {
        __AccessManaged_init(address(_accessManager));

        // Set minting timestamps
        lastRewardTimestamp = _firstRewardTimestamp;
        rewardDistributions[_firstRewardTimestamp] = DistributionStatus.MINTED;
        mintAllowedTimestamp = _mintAllowedTimestamp;
        distributionDelay = _distributionDelay;
        distributionAllowedTimestamp = _distributionAllowedTimestamp;

        // Initialize operator rewards settings with default values
        operatorRewardsManager = _operatorRewardsManager;
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
        uint256 newTimestamp = lastRewardTimestamp + STAKED_HYPER.epochDuration();
        require(block.timestamp >= newTimestamp, "HypMinter: Epoch not ready");

        // Update the last mint timestamp for next epoch calculation
        rewardDistributions[newTimestamp] = DistributionStatus.MINTED;
        lastRewardTimestamp = newTimestamp;

        // Mint the full amount to this contract
        HYPER.mint(address(this), MINT_AMOUNT);
        // Transfer operator rewards to operator rewards manager
        HYPER.transfer(operatorRewardsManager, getOperatorMintAmount());

        emit Mint();
    }

    /**
     * @notice Distributes minted HYPER tokens to stakers for a specific epoch
     * @param rewardTimestamp The timestamp of the epoch to distribute rewards for
     * @dev Can only be called after the distribution delay has passed since minting
     * @dev Distributes tokens to the rewards contract for stakers and transfers operator rewards directly
     * @dev Marks the distribution as completed to prevent double distribution
     */
    function distributeRewards(
        uint256 rewardTimestamp
    ) external {
        require(block.timestamp >= distributionAllowedTimestamp, "HypMinter: Distribution not allowed");

        // Check if the distribution is ready
        require(block.timestamp >= rewardTimestamp + distributionDelay, "HypMinter: Distribution not ready");

        DistributionStatus distributionStatus = rewardDistributions[rewardTimestamp];

        // Check if timestamp is valid and not already distributed
        require(
            distributionStatus == DistributionStatus.MINTED, "HypMinter: Rewards must be available for distribution"
        );

        // Update the distribution info
        rewardDistributions[rewardTimestamp] = DistributionStatus.DISTRIBUTED;

        // Distribute staking rewards
        REWARDS.distributeRewards({
            network: SYMBIOTIC_NETWORK,
            token: address(HYPER),
            amount: getStakingMintAmount(),
            data: abi.encode(rewardTimestamp, type(uint256).max, bytes(""), bytes(""))
        });
        emit Distribution(operatorBps);
    }

    /**
     * @notice Sets the delay between reward timestamp and when rewards can be distributed
     * @param _distributionDelay The new distribution delay in seconds (must be ≤ distributionDelayMaximum)
     * @dev Can only be called by authorized accounts with appropriate access control
     * @dev Emits DistributionDelaySet event upon successful update
     */
    function setDistributionDelay(
        uint256 _distributionDelay
    ) external restricted {
        require(_distributionDelay <= distributionDelayMaximum, "HypMinter: Distribution delay too large");
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
        require(bps < MAX_BPS, "HypMinter: Invalid BPS");
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
