// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';

import './curved/interfaces/IERC20Radiate.sol';
import './liquidity/interfaces/INonfungiblePositionManager.sol';
import './liquidity/libraries/TransferHelper.sol';

contract LiquidityManager is IERC721Receiver, AccessControl {
    address public constant nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    uint24 public constant poolFee = 100;

    // @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    // @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    modifier onlyRole(bytes32 role) {
        hasRole(role, msg.sender);
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), 'Not a UniswapV3 NFT.');
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) =
        INonfungiblePositionManager(nonfungiblePositionManager).positions(tokenId);
        // set the owner and data for position
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }

    // @notice Calls the mint function defined in periphery, mints the same amount of each token.
    // For this example we are providing 1000 token0 and 1000 token1 in liquidity
    // @return tokenId The id of the newly minted ERC721
    // @return liquidity The amount of liquidity for the position
    // @return amount0 The amount of token0
    // @return amount1 The amount of token1
    function mintNewPosition(address mintable, address token, uint256 amountToMint)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    )
    {
        address token0;
        address token1;

        if (token < mintable) {
            token0 = token;
            token1 = mintable;
        } else {
            token0 = mintable;
            token1 = token;
        }
        // For this example, we will provide equal amounts of liquidity in both assets.
        // Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.

        // transfer tokens to contract
        IERC20Radiate(mintable).mint(address(this), amountToMint);
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amountToMint);

        // Approve the position manager
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amountToMint);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amountToMint);

        // The values for tickLower and tickUpper may not work for all tick spacings.
        // Setting amount0Min and amount1Min to 0 is unsafe.
        INonfungiblePositionManager.MintParams memory params =
        INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: amountToMint,
            amount1Desired: amountToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Note that the pool defined by token0/token1 and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amountToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amountToMint - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amountToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amountToMint - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
    }

    // @notice Collects the fees associated with provided liquidity
    // @dev The contract must hold the erc721 token before it can collect fees
    // @param tokenId The id of the erc721 token
    // @return amount0 The amount of fees collected in token0
    // @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit
        // set amount0Max and amount1Max to type(uint128).max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params =
        INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(params);

        // send collected fees back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    // @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    // @param tokenId The id of the erc721 token
    // @return amount0 The amount received back in token0
    // @return amount1 The amount returned back in token1
    function decreaseLiquidityInHalf(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: halfLiquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).decreaseLiquidity(params);

        // send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    // @notice Increases liquidity in the current range
    // @dev Pool must be initialized already to add liquidity
    // @param tokenId The id of the erc721 token
    // @param amount0 The amount to add of token0
    // @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
    external
    returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    )
    {
        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountAdd0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amountAdd1);

        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amountAdd0);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amountAdd0,
            amount1Desired: amountAdd1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).increaseLiquidity(params);

        // Remove allowance and refund in both assets.
        /*
        if (amount0 < amountAdd0) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amountAdd0 - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
        */
    }

    // @notice Transfers funds to owner of NFT
    // @param tokenId The id of the erc721
    // @param amount0 The amount of token0
    // @param amount1 The amount of token1
    function _sendToOwner(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    // @notice Transfers the NFT to the owner
    // @param tokenId The id of the erc721
    function retrieveNFT(uint256 tokenId) external {
        // must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, 'Not the owner.');
        // remove information related to tokenId
        delete deposits[tokenId];
        // transfer ownership to original owner
        INonfungiblePositionManager(nonfungiblePositionManager).safeTransferFrom(address(this), msg.sender, tokenId);
    }
}