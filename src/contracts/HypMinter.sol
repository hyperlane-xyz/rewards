// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IDefaultStakerRewards} from "../interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";

/**
 * @title IERC20Mintable
 * @notice Extended ERC20 interface that includes minting functionality
 */
interface IERC20Mintable is IERC20 {
    /**
     * @notice Mints new tokens to a specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;
}

/**
 * @title HypMinter
 * @notice Contract responsible for minting and distributing HYPER tokens to stakers and operators
 * @dev Implements a 30-day epoch system for token distribution with configurable operator rewards
 */
contract HypMinter is AccessManagedUpgradeable {
    /**
     * @notice Initializes the HypMinter contract
     * @param firstTimestamp The initial timestamp for the first minting epoch
     * @param _accessManager The access manager contract for role-based permissions
     * @dev Sets up the contract with initial timestamp and approves HYPER tokens for rewards distribution
     */
    function initialize(uint256 firstTimestamp, AccessManager _accessManager) external initializer {
        lastMintTimestamp = firstTimestamp;
        __AccessManaged_init(address(_accessManager));
        HYPER.approve(address(REWARDS), type(uint256).max);
    }

    /**
     * @notice Timestamp of the last minting operation
     * @dev Used to enforce 30-day epochs between minting operations
     */
    uint256 public lastMintTimestamp;

    /**
     * @notice Total amount of HYPER tokens minted per epoch
     * @dev Fixed at 666,667 HYPER tokens per minting cycle
     */
    uint256 public constant MINT_AMOUNT = 666_667 ether;

    /**
     * @notice The HYPER token contract with minting capabilities
     * @dev Mainnet address of the HYPER ERC20 token
     */
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
     * @notice Mints HYPER tokens and distributes them to stakers and operators
     * @dev Can only be called after the start time (2025-10-17 23:14:47 GMT) and respects 30-day epochs
     * @dev Mints the full MINT_AMOUNT and splits it between stakers and operators based on operatorBps
     */
    function mintAndDistribute() external {
        // 2025-10-17 23:14:47 GMT
        require(block.timestamp >= 1_760_742_887, "Not started");

        HYPER.mint(address(this), MINT_AMOUNT);

        _distributeStakingRewards();
        _distributeOperatorRewards();
    }

    /**
     * @notice Distributes the staking portion of minted tokens to the rewards contract
     * @dev Enforces 30-day epochs and updates the lastMintTimestamp
     * @dev Distributes tokens to the REWARDS contract for the SYMBIOTIC_NETWORK
     */
    function _distributeStakingRewards() internal {
        // Fixed 30 day epochs
        uint256 newTimestamp = lastMintTimestamp + 30 days;
        require(block.timestamp >= newTimestamp);
        lastMintTimestamp = newTimestamp;

        // Only distribute staking rewards portion of mint
        /// @dev This reverts if not in the past, but we did a require above anyway
        REWARDS.distributeRewards({
            network: SYMBIOTIC_NETWORK,
            token: address(HYPER),
            amount: getStakingMintAmount(),
            data: abi.encode(newTimestamp, 0, bytes(""), bytes(""))
        });
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
     * @notice Maximum basis points value (100%)
     * @dev Used for percentage calculations, where 10,000 = 100%
     */
    uint256 public constant MAX_BPS = 10_000;

    /**
     * @notice Basis points allocated to operator rewards
     * @dev Default is 1,000 basis points (10%). Can be modified by authorized accounts
     */
    uint256 public operatorBps = 1000;

    /**
     * @notice Sets the percentage of rewards allocated to operators
     * @param bps The new operator rewards percentage in basis points (e.g., 1000 = 10%)
     * @dev Can only be called by authorized accounts (AW Multisig) with 30-day delay
     */
    function setOperatorRewardsBps(
        uint256 bps
    ) external restricted {
        require(bps <= MAX_BPS, "Invalid BPS");
        operatorBps = bps;
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
     * @notice Address that receives operator rewards
     * @dev Should be the Foundation multisig address
     */
    address public operatorRewardsManager = 0x2522d3797411Aff1d600f647F624713D53b6AA11;

    /**
     * @notice Distributes operator rewards by transferring tokens directly
     * @dev Transfers the operator portion of minted tokens to the operatorRewardsManager
     */
    function _distributeOperatorRewards() internal {
        HYPER.transfer(operatorRewardsManager, getOperatorMintAmount());
    }

    /**
     * @notice Updates the address that receives operator rewards
     * @param _manager The new operator rewards manager address
     * @dev Can only be called by authorized accounts (AW Multisig) with 30-day delay
     */
    function setOperatorRewardsManager(
        address _manager
    ) external restricted {
        operatorRewardsManager = _manager;
    }
}
