// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {IVault} from "../lib/core/src/interfaces/vault/IVault.sol";
import {IDefaultStakerRewards} from "../src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IstETH {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IwstETH {
    function stETH() external view returns (address);
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract StakingTest is Script {
    // Fixed amount for minting: 0.0001 ETH
    uint256 public constant MINT_AMOUNT = 0.0001 ether;
    
    // Contract addresses (these would need to be set based on the network)
    address public stETH;
    address public wstETH;
    address public vault;
    address public stakerRewards;
    
    function setUp() public {
        // Set contract addresses based on chain ID
        if (block.chainid == 1) {
            // Mainnet
            stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        } else if (block.chainid == 17000) {
            // Holesky
            stETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
            wstETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
            vault = 0x0351bE785c8Abfc81e8d8C2b6Ef06A7fc62478a0;
        } else if (block.chainid == 11155111) {
            // Sepolia
            stETH = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af;
            wstETH = 0xB82381A3fBD3FaFA77B3a7bE693342618240067b;
        }
        // Note: vault and stakerRewards addresses would need to be provided
        // or deployed separately depending on your specific setup
    }
    
    /**
     * @notice Mint stETH from ETH and convert to wstETH
     * @dev Uses fixed amount of 0.0001 ETH
     * @return wstETHAmount Amount of wstETH received after wrapping
     */
    function mint() public returns (uint256 wstETHAmount) {
        address sender = msg.sender;
        require(stETH != address(0), "stETH address not set");
        require(wstETH != address(0), "wstETH address not set");
        
        console2.log("Starting mint process with", MINT_AMOUNT, "ETH");
        
        // Get initial balances
        uint256 initialStETHBalance = IstETH(stETH).balanceOf(sender);
        uint256 initialWstETHBalance = IwstETH(wstETH).balanceOf(sender);
        
        // Mint stETH by sending ETH to stETH contract
        vm.startBroadcast(sender);
        (bool success,) = stETH.call{value: MINT_AMOUNT}("");
        require(success, "Failed to mint stETH");
        
        // Get stETH balance after minting
        uint256 stETHBalance = IstETH(stETH).balanceOf(sender);
        uint256 stETHReceived = stETHBalance - initialStETHBalance;
        
        console2.log("Minted", stETHReceived, "stETH");
        
        // Approve wstETH contract to spend stETH
        require(IstETH(stETH).approve(wstETH, stETHReceived), "Failed to approve stETH");
        
        // Wrap stETH to wstETH
        wstETHAmount = IwstETH(wstETH).wrap(stETHReceived);
        vm.stopBroadcast();
        
        // Verify wstETH balance increased
        uint256 finalWstETHBalance = IwstETH(wstETH).balanceOf(sender);
        uint256 wstETHActualReceived = finalWstETHBalance - initialWstETHBalance;
        
        console2.log("Wrapped to", wstETHActualReceived, "wstETH");
        require(wstETHActualReceived > 0, "No wstETH received");
        
        return wstETHActualReceived;
    }
    
    /**
     * @notice Deposit wstETH into a vault
     * @return depositedAmount Real amount deposited
     * @return mintedShares Amount of shares minted
     */
    function deposit() public returns (uint256 depositedAmount, uint256 mintedShares) {
        uint amount = MINT_AMOUNT;
        require(vault != address(0), "Vault address not set");
        require(wstETH != address(0), "wstETH address not set");
        require(amount > 0, "Amount must be greater than 0");

        console2.log("Depositing", amount);
        
        // Check wstETH balance
        address sender = msg.sender;
        uint256 wstETHBalance = IwstETH(wstETH).balanceOf(sender);
        require(wstETHBalance >= amount, "Insufficient wstETH balance");
        
        // Approve vault to spend wstETH
        vm.startBroadcast(sender);
        require(IwstETH(wstETH).approve(vault, amount), "Failed to approve vault");
        
        // Deposit into vault
        (depositedAmount, mintedShares) = IVault(vault).deposit(sender, amount);
        vm.stopBroadcast();
        console2.log("Deposited %s wstETH, minted %s shares", depositedAmount, mintedShares);
        
        return (depositedAmount, mintedShares);
    }
    
    /**
     * @notice Distribute rewards through DefaultStakerRewards contract
     * @param network Network address to distribute rewards for
     * @param token Token address for rewards
     * @param amount Amount of tokens to distribute
     * @param data Additional data for reward distribution
     */
    function distributeRewards(
        address network,
        address token,
        uint256 amount,
        bytes calldata data
    ) public {
        require(stakerRewards != address(0), "StakerRewards address not set");
        require(network != address(0), "Invalid network address");
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        
        console2.log("Distributing", amount, "tokens for network", network);
        
        // Check token balance
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        require(tokenBalance >= amount, "Insufficient token balance");
        
        // Approve stakerRewards contract to spend tokens
        require(IERC20(token).approve(stakerRewards, amount), "Failed to approve token");
        
        // Distribute rewards
        IDefaultStakerRewards(stakerRewards).distributeRewards(network, token, amount, data);
        
        console2.log("Successfully distributed rewards");
    }
    
    /**
     * @notice Set vault address (for testing/deployment)
     * @param _vault Vault contract address
     */
    function setVault(address _vault) public {
        require(_vault != address(0), "Invalid vault address");
        vault = _vault;
        console2.log("Vault address set to:", _vault);
    }
    
    /**
     * @notice Set staker rewards address (for testing/deployment)
     * @param _stakerRewards StakerRewards contract address
     */
    function setStakerRewards(address _stakerRewards) public {
        require(_stakerRewards != address(0), "Invalid staker rewards address");
        stakerRewards = _stakerRewards;
        console2.log("StakerRewards address set to:", _stakerRewards);
    }
    
    /**
     * @notice Complete workflow: mint, deposit, and distribute rewards
     * @param onBehalfOf Address to deposit on behalf of
     * @param network Network address for reward distribution
     * @param rewardToken Token for rewards distribution
     * @param rewardAmount Amount of rewards to distribute
     * @param data Additional data for reward distribution
     */
    function fullWorkflow(
        address onBehalfOf,
        address network,
        address rewardToken,
        uint256 rewardAmount,
        bytes calldata data
    ) public {
        console2.log("Starting full staking workflow...");
        
        // Step 1: Mint stETH and wrap to wstETH
        uint256 wstETHAmount = mint();
        
        // Step 2: Deposit wstETH into vault
        deposit();
        
        // Step 3: Distribute rewards (if token balance available)
        if (IERC20(rewardToken).balanceOf(address(this)) >= rewardAmount) {
            distributeRewards(network, rewardToken, rewardAmount, data);
        } else {
            console2.log("Skipping reward distribution - insufficient token balance");
        }
        
        console2.log("Full workflow completed");
    }

    
    // Allow contract to receive ETH
    receive() external payable {}
} 