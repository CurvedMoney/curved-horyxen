// SPDX-License-Identifier: MIT

pragma solidity >=0.7.5;

/**
 * @dev Collection of functions related to the Horyxen Liquidity Engine
 */

interface ILiquidityEngine {
    function getReward(uint256 _tokens, uint256[] calldata _tokenIDs) external returns (uint256 reward);

    function getRate(uint256 _difficulty, address _poolAddress) external returns (uint256 rate);

    function generateMintConfiguration(uint256 _tokens, uint256 _type, uint256[] calldata _tokenIDs)
    external
    returns (
        uint256 requiredXENFTs,
        uint256 requiredVMUs,
        uint256 excessVMUs,
        uint256[] memory resignerIDs,
        uint256 reward
    );

    function updateTerm(uint256 _term) external;

    function updateTransactionReward(uint256 _transactionReward) external;

    function updateWalletDelta(uint256 _walletDelta) external;

    function transactWalletDelta(uint256 _walletDelta, address _mintable) external;
}
