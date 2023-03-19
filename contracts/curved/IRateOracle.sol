// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the Curved Treasury
 */

interface IRateOracle {
    function active() external view returns (bool);

    function getEasingAdvice(address sender, address recipient, uint256 rate, uint256 amount) external view returns (uint256);

    function getEasingRate(address user, address radiateSourceAddress, address radiateTargetAddress) external view returns (uint256);

    function getReserves() external view returns (uint256);
}