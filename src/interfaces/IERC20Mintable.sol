// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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
