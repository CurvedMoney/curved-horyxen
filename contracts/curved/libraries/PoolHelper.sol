// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library PoolHelper {
    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     *      Base on OpenZeppelin `toString` method from `String` library
     */
    function getReserves(address poolAddress) internal view returns (uint256 reserve0, uint256 reserve1) {
        IUniswapV3Pool v3Pool = IUniswapV3Pool(poolAddress);
        IERC20  token0 = IERC20(v3Pool.token0());
        IERC20  token1 = IERC20(v3Pool.token1());

        reserve0 = token0.balanceOf(poolAddress);
        reserve1 = token1.balanceOf(poolAddress);
    }

}
