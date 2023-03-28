// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

import "../contracts/utils/math/Math.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

library PoolHelper {
    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
            Base on OpenZeppelin `toString` method from `String` library
     */
    function calculateToken0Amount(uint256 liquidity, uint256 sqrtPriceCurrent, uint256 sqrtPriceLow, uint256 sqrtPriceHigh) private pure returns (uint256) {
        sqrtPriceCurrent = Math.max(Math.min(sqrtPriceCurrent, sqrtPriceHigh), sqrtPriceLow);

        return liquidity * (sqrtPriceHigh - sqrtPriceCurrent) / (sqrtPriceCurrent * sqrtPriceHigh);
    }

    function calculateToken1Amount(uint256 liquidity, uint256 sqrtPriceCurrent, uint256 sqrtPriceLow, uint256 sqrtPriceHigh) private pure returns (uint256) {
        sqrtPriceCurrent = Math.max(Math.min(sqrtPriceCurrent, sqrtPriceHigh), sqrtPriceLow);

        return liquidity * (sqrtPriceCurrent - sqrtPriceLow);
    }

    function getReserves(address poolAddress) internal view returns (uint256 reserve0, uint256 reserve1) {
        IUniswapV3Pool v3Pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();

        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;
        int24 TICK_SPACING = v3Pool.tickSpacing();
        int128 liquidity;

        uint256 sqrtPriceCurrent = sqrtPriceX96 * (2**96);
        uint256 sqrtPriceLow;
        uint256 sqrtPriceHigh;

        for (int24 tick = MIN_TICK; tick != MAX_TICK; tick += TICK_SPACING) {
            (, int128 liquidityNet,,,,,,) = v3Pool.ticks(tick);

            liquidity = liquidity + liquidityNet;
            sqrtPriceLow = (10001 ** (uint256(tick) / 2)) / 1e4;
            sqrtPriceHigh = (10001 ** ((uint256(tick + TICK_SPACING)) / 2)) / 1e4;

            reserve0 += calculateToken0Amount(uint256(liquidity), sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh);
            reserve1 += calculateToken1Amount(uint256(liquidity), sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh);
        }
    }
}
