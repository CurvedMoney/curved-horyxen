// SPDX-License-Identifier: GPL-2.0-or-later

import '@openzeppelin/contracts/access/AccessControl.sol';

import './curved/interfaces/IERC20Radiate.sol';
import "./curved/interfaces/IXEN.sol";
import "./curved/interfaces/IXENFT.sol";
import "./curved/contracts/utils/math/CurvedSafeMath.sol";
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
     * @dev Reward multiplier for transacting mints
     */
    uint256 public rewardMultiplier;

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
     * @dev Transaction participants
     */
    address[] public transactorList;

    /**
     * @dev Current new wallets
     */
    uint256 public walletDelta;

    /**
     * @dev Helper interfaces
     */
    IXEN public xenCrypto;
    IXENFT public xenTorrent;

    /**
     * @dev Current transactor index
     */
    uint8 private transactorIndex;

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

    constructor(address _liquidityTargetAddress, address _liquidityTargetMinterAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        xenCrypto = IXEN(_liquidityTargetAddress);

        xenTorrent = IXENFT(_liquidityTargetMinterAddress);

        _base = 1e18;

        rewardMultiplier = 15e17;

        term = 100;

        termChanges = 1;
    }

    function getReward(uint256 _tokens, uint256[] _tokenIDs) returns (uint256 reward) {
        uint256 totalMinted;

        for (uint256 i = 0; i < _tokenIDs.length; i++) {
            uint256 mintInfo = xenTorrent.mintInfo(_tokenIDs[i]);
            uint256 rankDelta = CurvedSafeMath.sub(xenCrypto.globalRank(), mintInfo.getRank());
            uint256 estimate = (mintInfo.getTerm() * CurvedSafeMath.log2(CurvedSafeMath.max(rankDelta, 2)) * (mintInfo.getAmp() || 0) * (1 + (mintInfo.getEAA() || 0) / 100)).mul(_base);

            totalMinted += estimate * xenTorrent.vmuCount(_tokenIDs[i]);
        }

        require(totalMinted >= _tokens, "LiquidityEngine: Mint is invalid.");

        return (totalMinted.sub(_tokens).mul(rewardMultiplier));
    }

    function getRate(uint256 _difficulty, address _poolAddress) public returns (uint256 rate) {
        (uint256 reserve0, uint256 reserve1) = PoolHelper.getReserves(_poolAddress);

        return _difficulty.mul(100).mul(uint256(reserve0)).div(uint256(reserve1));
    }

    function generateMintConfiguration(uint256 _tokens, uint256 _type, uint256[] _tokenIDs)
    internal
    returns (
        uint256 requiredXENFTs,
        uint256 requiredVMUs,
        uint256 excessVMUs,
        uint256 resignerIDs,
        uint256 reward
    ) {
        requiredXENFTs = 0;
        requiredVMUs = 0;
        excessVMUs = 0;
        resignerIDs = uint256[];
        reward = 0;

        if (_type == CLAIM) {
            require(_tokens > 0, "LiquidityEngine: Must select token amount.");

            uint256 estimate = (term * CurvedSafeMath.log2(CurvedSafeMath.max(walletDelta, 2)) * (xenCrypto.getCurrentAMP() || 0) * (1 + (xenCrypto.getCurrentEAAR() || 0) / 100)).mul(_base);
            uint256 estimatedXENFTs = 1;
            uint256 estimatedVMUs = (estimate / _tokens);

            // Determine if estimated VMUs `(estimate / _tokens)` is greater than maximum allowed per XENft
            if (estimatedVMUs > maxVMUs) {
                estimatedXENFTs = estimatedVMUs / maxVMUs;
                uint256 excessVMUs = estimatedVMUs / maxVMUs;

                return (estimatedXENFTs, estimatedVMUs, excessVMUs, uint256[], 0);
            }

            requiredXENFTs = estimatedXENFTs;
            requiredVMUs = estimatedVMUs;
            excessVMUs = excessVMUs;
            resignerIDs = uint256[];
            reward = 0;

            // TODO - Evaluate reserve determine if a mint is necessary on claim and generate reward
        } else if (_type == MINT) {
            // If mint is necessary return list of NFT IDs

            requiredXENFTs = estimatedXENFTs;
            requiredVMUs = estimatedVMUs;
            excessVMUs = 0;
            resignerIDs = _tokenIDs;
            reward = getReward(_tokens, _tokenIDs);
        }
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

    function updateWalletDelta(uint256 _walletDelta) public onlyRole(DEFAULT_ADMIN_ROLE) {
        walletDelta = _walletDelta;
    }

    function transactWalletDelta(uint256 _walletDelta, address _mintable) public onlyRole(TRANSACTOR_ROLE) {
        transactorIndex += 1;
        transactorList.push(msg.sender);

        if (transactorIndex % 16 == 0) {
            for (uint256 i = 0; i < transactorList.length - 1; i++) {
                IERC20Radiate(_mintable).mint(transactorList, transactionReward);
            }

            IERC20Radiate(_mintable).mint(msg.sender, transactionReward.mul(rewardMultiplier));

            onTransact(msg.sender, 1, reward, block.timestamp);

            delete transactorList;
        }
    }
}
