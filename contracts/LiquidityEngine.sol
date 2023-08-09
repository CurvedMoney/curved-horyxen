// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/access/AccessControl.sol';

import "./curved/contracts/utils/math/CurvedSafeMath.sol";
import './curved/interfaces/IERC20Radiate.sol';
import "./curved/interfaces/IXEN.sol";
import "./curved/interfaces/IXENFT.sol";
import "./curved/libraries/PoolHelper.sol";
import './liquidity/libraries/MintInfo.sol';

contract LiquidityEngine is AccessControl {
    using CurvedSafeMath for uint256;
    using MintInfo for uint256;

    event onTransact(
        address indexed transactor,
        uint256 transactionType,
        uint256 reward,
        uint256 time
    );

    /**
     * @dev Feature accessibility mapping
     * `type` (1) - Rank delta transactions enabled
     */
    mapping(uint256 => bool) public flags;

    /**
     * @dev Reward multiplier for transacting mints
     */
    uint256 public rewardMultiplier;

    /**
     * @dev Current new ranks
     */
    uint256 public rankDelta;

    /**
     * @dev Un-transacted rank deltas
     */
    uint256 public rankDeltaTransactionsEnabled;

    /**
     * @dev Current mint termination period (days)
     */
    uint256 public term;

    /**
     * @dev Term average used for stats
     */
    uint256 public termAverage;

    /**
     * @dev Tracks term updates
     */
    uint256 public termChanges;

    /**
     * @dev Transaction reward
     */
    uint256 public transactionReward;

    /**
     * @dev Helper interfaces
     */
    IXEN public xenCrypto;
    IXENFT public xenTorrent;

    /**
     * @dev ERC-20 number system
     */
    uint256 private _base;

    // =---------- CONTRACT CONSTANTS

    /**
     * @dev Decimal amplification
     */
    uint256 internal constant magnitude = 18446744073709551616;
    uint256 public constant maxVMUs = 128;

    uint256 public constant CLAIM = 0;
    uint256 public constant MINT = 1;
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant TRANSACTOR_ROLE = keccak256("TRANSACTOR_ROLE");

    modifier onlyRole(bytes32 role) {
        hasRole(role, msg.sender);
        _;
    }

    constructor(address _liquidityTargetAddress, address _liquidityTargetMinterAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        xenCrypto = IXEN(_liquidityTargetAddress);

        xenTorrent = IXENFT(_liquidityTargetMinterAddress);

        _base = 1e18;

        rewardMultiplier = 15e17;

        term = 100;

        termChanges = 1;
    }

    function getReward(uint256 _tokens, uint256[] calldata _tokenIDs) public view returns (uint256 reward) {
        uint256 totalMinted;

        for (uint256 i = 0; i < _tokenIDs.length; i++) {
            uint256 mintInfo = xenTorrent.mintInfo(_tokenIDs[i]);
            uint256 localRankDelta = CurvedSafeMath.sub(xenCrypto.globalRank(), mintInfo.getRank());

            uint256 estimate = xenCrypto.getGrossReward(localRankDelta, mintInfo.getAMP(), mintInfo.getTerm(), mintInfo.getEAA()).mul(_base);

            totalMinted += estimate * xenTorrent.vmuCount(_tokenIDs[i]);
        }

        require(totalMinted >= _tokens, "LiquidityEngine: Mint is invalid.");

        return (totalMinted.sub(_tokens).mul(rewardMultiplier));
    }

    function getRate(uint256 _difficulty, address _poolAddress) public view returns (uint256 rate) {
        (uint256 reserve0, uint256 reserve1) = PoolHelper.getReserves(_poolAddress);

        return _difficulty.mul(100).mul(uint256(reserve0)).div(uint256(reserve1));
    }

    function generateMintConfiguration(uint256 _tokens, uint256 _type, uint256[] calldata _tokenIDs)
    external
    view
    returns (
        uint256 requiredXENFTs,
        uint256 requiredVMUs,
        uint256 excessVMUs,
        uint256[] memory resignerIDs,
        uint256 reward
    ) {
        requiredXENFTs = 0;
        requiredVMUs = 0;
        excessVMUs = 0;
        resignerIDs = (new uint256[](0));
        reward = 0;

        if (_type == CLAIM) {
            require(_tokens > 0, "LiquidityEngine: Must select token amount.");

            uint256 estimate = xenCrypto.getGrossReward(rankDelta, xenCrypto.getCurrentAMP(), term, xenCrypto.getCurrentEAAR()).mul(_base);
            uint256 estimatedXENFTs = 1;
            uint256 estimatedVMUs = (estimate / _tokens);

            // Determine if estimated VMUs `(estimate / _tokens)` is greater than maximum allowed per XENft
            if (estimatedVMUs > maxVMUs) {
                estimatedXENFTs = estimatedVMUs / maxVMUs;
                excessVMUs = estimatedVMUs / maxVMUs;

                return (estimatedXENFTs, estimatedVMUs, excessVMUs, resignerIDs, 0);
            }

            // TODO - Evaluate reserve determine if a mint is necessary on claim and generate reward

            requiredXENFTs = estimatedXENFTs;
            requiredVMUs = estimatedVMUs;
            reward = 0;
        } else if (_type == MINT) {
            // If mint is necessary return list of NFT IDs

            requiredXENFTs = 0;
            requiredVMUs = 0;
            excessVMUs = 0;
            resignerIDs = _tokenIDs;
            reward = getReward(_tokens, _tokenIDs);
        }
    }

    /**
     * @dev Toggles `flag`
     * `flag` (1) - Rank delta transactions enabled - Allow `TRANSACTOR_ROLE` to update rankDelta
     */
    function updateFlags(uint256 _flag, bool _enable) public onlyRole(GOVERNOR_ROLE) {
        flags[_flag] = _enable;
    }

    function updateTerm(uint256 _term) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 previousAverage = termAverage * termChanges;

        termChanges += 1;
        termAverage = (previousAverage + (_term * 1e6)) / termChanges;
        term = _term;
    }

    function updateTransactionReward(uint256 _transactionReward) public onlyRole(DEFAULT_ADMIN_ROLE) {
        transactionReward = _transactionReward;
    }

    function updateRankDelta(uint256 _rankDelta) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rankDelta = _rankDelta;
    }

    function transactRankDelta(uint256 _rankDelta, address _mintable, address[] calldata transactors) public onlyRole(TRANSACTOR_ROLE) {
        require(flags[1], "LiquidityEngine: Rank delta transactions not enabled.");

        for (uint256 i = 0; i < transactors.length - 1; i++) {
            IERC20Radiate(_mintable).mint(transactors[i], transactionReward);

            onTransact(transactors[i], 1, transactionReward, block.timestamp);
        }

        IERC20Radiate(_mintable).mint(msg.sender, transactionReward.mul(rewardMultiplier));

        onTransact(msg.sender, 1, transactionReward.mul(rewardMultiplier), block.timestamp);

        rankDelta = _rankDelta;
    }
}
