// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.7.5;

interface IERC20Radiate {
    /**
     * @dev Creates `tAmount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - the caller must have minter role.
     */
    function mint(address recipient, uint256 amountIn) external;
}
