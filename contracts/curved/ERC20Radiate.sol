// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.7.5;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./contracts/access/AccessControl.sol";
import "./contracts/utils/math/SafeMath.sol";
import "./interfaces/ILiquidityManager.sol";
import "./interfaces/IQuoterV2.sol";
import "./interfaces/IRateOracle.sol";
import "./libraries/PoolHelper.sol";

/*
 * @dev ERC20Radiate is a yield protocol with configurable supply-dependent rated contract functions
 * (deposit, withdraw, et cetra) that are distributed to Radiators.
 *
 * Attributes (rates, reserve balance, debt, claims, et cetra) are configurable by the contract owner.
 */

contract ERC20Radiate is ERC20, CurvedAccessControl {
    using CurvedSafeMath for uint256;

    // =---------- EVENTS

    event onClaim(
        address indexed customerAddress,
        uint256 radiateTargetWithdrawn,
        uint256 timestamp,
        uint256 claimSession
    );

    event onRateOracleUpdate(
        address indexed oracle
    );

    event onReconciliation(
        uint256 amount,
        uint256 timestamp
    );

    event onReserveIncrease(
        address indexed from,
        uint256 amount,
        uint256 timestamp
    );

    event onTokenConversion(
        address indexed customerAddress,
        uint256 tokensConverted,
        uint256 timestamp
    );

    event onTokenLiquidation(
        address indexed customerAddress,
        uint256 tokensLiquidated,
        uint256 timestamp
    );

    event onTokenAllocation(
        address indexed customerAddress,
        uint256 incomingTokens,
        uint256 tokensPending,
        uint256 timestamp
    );

    event onTokenWrap(
        address indexed customerAddress,
        uint256 incomingTokens,
        uint256 tokensMinted,
        uint256 timestamp
    );

    event onTokenUnwrap(
        address indexed customerAddress,
        uint256 tokensBurned,
        uint256 radiateTargetEarned,
        uint256 timestamp
    );

    event onTransact(
        address indexed transactor,
        uint256 time
    );

    event onWithdraw(
        address indexed customerAddress,
        uint256 radiateTargetWithdrawn,
        uint256 timestamp
    );

    // =---------- MODIFIERS

    /**
     * @dev Only addresses with tokens
     */
    modifier onlyRadiators {
        require(accountTokens() > 0);
        _;
    }

    /**
     * @dev Only addresses with claims
     */
    modifier onlyClaimants {
        require(accountClaims() > 0);
        _;
    }

    /**
     * @dev Only addresses with shares
     */
    modifier onlyRecipients {
        require(accountYield() > 0);
        _;
    }

    // =---------- DATA STRUCTURES

    struct Statement {
        uint256 allocated;
        uint256 allocations;
        uint256 claimed;
        uint256 claims;
        uint256 deposited;
        uint256 guaranteed;
        uint256 liquidated;
        uint256 liquidations;
        uint256 paid;
        uint256 rebated;
        uint256 receipts;
        uint256 received;
        uint256 transferred;
        uint256 transfers;
        uint256 withdrawals;
        uint256 withdrawn;
        uint256 wrapped;
        uint256 wraps;
    }

    struct Treasurer {
        uint256 balanceAllocated;
        address contractAddress;
        uint256 reserveLimit;
        uint256 status;
    }

    // =---------- CONFIGURABLES

    /**
     * @dev Feature accessibility mapping
     * `type` (1) - Rate allocation enabled
     * `type` (2) - ERC20Radiate position unwrap enabled
     * `type` (3) - External allocations enabled
     * `type` (4) - Operational claims enabled
     * `type` (5) - ERC20Radiate position transfer enabled
     * `type` (6) - Account-based rates enabled
     * `type` (7) - Allocated balance (allocation) withdraw enabled
     * `type` (8) - Instant rebates enabled
     * `type` (9) - Reserve allocation enabled
     * `type` (10) - Reconciliation enabled
     * `type` (11) - Oracle enabled
     * `type` (12) - Liquidity based network rate calculation enabled
     * `type` (13) - Credit rate determinant
     * `type` (14) - Pair has liquidity
     * `type` (15) - Reserve-based minting
     */
    mapping(uint256 => bool) public flags;

    /**
     * @dev Rate structure of percentages applied to user transactions
     * `type` (0) - Operational rate
     * `type` (1) - Network rate
     * `type` (2) - Unwrap rate
     * `type` (3) - Withdrawal rate
     * `type` (4) - Transfer rate
     * `type` (5) - Rebate rate
     * `type` (6) - Allocation rate
     * `type` (7) - Credit rate
     */
    mapping(uint256 => uint256) internal systemRates;

    /**
     * @dev Rate structure of percentages applied to user balances
     */
    mapping(uint256 => mapping(address => uint256)) internal userRates;

    /**
     * @dev Pay rate for yield pool.
     * `liquidityRateLimit_` - Rate limit for network rate allocation - Configurable
     * `yieldRate_` - Base rate paid to all users - Configurable
     * `yieldMinRate_` - Rate assigned to users that have hit credit limit- Configurable
     */
    uint256 internal liquidityRateLimit_;
    uint256 internal yieldMinRate_;
    uint256 internal yieldRate_;

    /**
     * @dev Balance of supply applied to ERC20Radiate operations i.e.
     * (marketing/promotions, human resources, et cetra)
     */
    mapping(uint256 => uint256) public operationalReserve;

    // =---------- ACCOUNT LEDGERS

    /**
     * @dev View of the ERC20Radiate's accounting
     */
    mapping(address => Statement) internal statementLedger_;

    /**
     * @dev Collection of ERC20Radiate treasurers
     */
    mapping(address => Treasurer) internal treasurerCollection_;

    /**
     * @dev Ledger of claims available per session
     */
    mapping(uint256 => mapping(address => uint256)) internal claimsLedger_;

    /**
     * @dev Ledger of user ERC20Radiate
     */
    mapping(address => uint256) internal balances_;

    /**
     * @dev Ancillary accounts (int256)
     */
    mapping(uint256 => uint256) internal claimSupply_;
    mapping(address => uint256) internal allocationsTo_;

    /**
     * @dev Balance of supply allocated to ERC20Radiate treasurer operations
     * `debtReserve` - Allocated supply for collateralized tokens
     * `initialRate` - Rate that {raditateTarget} applies initial liquidity
     */
    uint256 public debtReserve;
    uint256 public initialRate;

    /**
     * @dev Share representation of holder's supply, debtor's supply, and yield rate, respectively
     */
    uint256 internal debtSupply_;
    uint256 internal shareSupply_;
    uint256 internal tokenSupply_;
    uint256 internal yieldReturn_;
    uint256 internal yieldSupply_;
    uint256 internal yieldPerShare_;

    /**
     * @dev ERC20Radiate analytics (public)
     */
    uint256 public allocated;
    uint256 public claimed;
    uint256 public deposited;
    uint256 public guaranteed;
    uint256 public liquidated;
    uint256 public liquidations;
    uint256 public paid;
    uint256 public rebated;
    uint256 public transactions;
    uint256 public transferred;
    uint256 public unwrapped;
    uint256 public users;
    uint256 public withdrawn;
    uint256 public wrapped;

    /**
     * @dev ERC20Radiate analytics (public / internal)
     * `yieldIteration` - Minimum amount of time between transact calls distributing yield.
     * `yieldTimestamp` - Epoch timestamp of latest request distributing yield.
     */
    uint256 public yieldIteration;
    uint256 public yieldTimestamp;

    /**
     * @dev Address references (public)
     * `operationalLedgerLength` - Tracks size of the list of {operationalAccount} receivers.
     * `operationalAddress` - Address receiving realtime wraps from operational account - configurable.
     * `liquidationPath` - Uniswap compatible path for unwraps and liquidations.
     * `reconciliationPath` - Uniswap compatible path for reconciling withdrawals.
     */
    uint8 public operationalLedgerLength;
    mapping (uint => address payable) operationalAddress;
    address payable public liquidityManagerAddress;
    address payable public radiateSourceAddress;
    address[] public liquidationPath;
    address[] public reconciliationPath;
    address public poolAddress;

    /**
     * @dev Session-based index tracking treasury claimants, sessions are iterated on resetClaimants
     */
    uint256 public claimSession;

    /**
     * @dev Type to param `type`
     * `type` (0) - Operational claims
     * `type` (1) - Affiliate/referral claims
     */
    uint256 public claimType;

    /**
     * @dev Helper interfaces
     */
    IQuoterV2 public v3Quoter;
    IUniswapV3Factory public v3Factory;
    IUniswapV3Pool public v3Pool;
    IRateOracle public rateOracle;
    ILiquidityManager public liquidityManager;

    ERC20 internal radiateSource;

    /**
     * @dev ERC-20 attributes
     */
    uint8 internal _decimals;
    string internal _name;
    string internal _symbol;

    /**
     * @dev ERC-20 number system
     */
    uint256 private _base;

    /**
     * @dev ERC-20 allowance mapping
     */
    mapping(address => mapping(address => uint256)) internal _allowances;

    // =---------- CONTRACT CONSTANTS

    /**
     * @dev Decimal amplification
     */
    uint256 internal constant magnitude = 18446744073709551616;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TRANSACTOR_ROLE = keccak256("TRANSACTOR_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    constructor(address _radiateSourceAddress, address _liquidityManagerAddress, uint256 _initialRate, string memory _radiatorName, string memory _radiatorSymbol) ERC20(_radiatorName, _radiatorSymbol) {
        flags[1] = true;                    // Rate allocation enabled
        flags[4] = true;                    // Operational allocations (dev/referrals) enabled
        flags[8] = false;                   // Instant rebate enabled
        flags[15] = true;                   // Share minting derived from LP reserves

        systemRates[0] = 333e16;            // 3.33% - Referral rate
        systemRates[1] = 100e18;            // 100% - Network allocation rate
        systemRates[5] = 20e18;             // 20% - Instant rebate rate
        systemRates[7] = 333e18;            // 333% - Maximum recipient limit

        yieldMinRate_ = 333e14;             // 0.0333% - Max recipient rate
        yieldRate_ = 333e16;                // 3.33% - Daily pool allocation
        yieldIteration = 12 seconds;
        yieldSupply_ = 0;
        yieldTimestamp = block.timestamp;

        liquidityRateLimit_ = 150e18;       // 150% - Maximum network rate allocation

        initialRate = _initialRate;

        _decimals = 18;
        _base = 10 ** (uint256(_decimals));
        _name = _radiatorName;
        _symbol = _radiatorSymbol;

        _grantRole(DEFAULT_ADMIN_ROLE, __msgSender());
        _grantRole(GOVERNOR_ROLE, __msgSender());
        _grantRole(MINTER_ROLE, __msgSender());
        _grantRole(MINTER_ROLE, _liquidityManagerAddress);
        _grantRole(TREASURER_ROLE, __msgSender());

        radiateSourceAddress = payable(_radiateSourceAddress);
        radiateSource = ERC20(radiateSourceAddress);
        radiateSource.approve(__msgSender(), 115792089237316195423570985008687907853269984665640564039457584007913129639935);

        liquidityManagerAddress = payable(_liquidityManagerAddress);
        liquidityManager = ILiquidityManager(_liquidityManagerAddress);
        liquidityManager.grantRole(DEFAULT_ADMIN_ROLE, address(this));

        v3Quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        operationalLedgerLength = 1;
        operationalAddress[0] = payable(__msgSender());

        poolAddress = v3Factory.getPool(radiateSourceAddress, address(this), 100);

        uint160 sqrtPriceX96 = 1 * 2**96;

        if (poolAddress == address(0)) {
            flags[14] = false;
            poolAddress = v3Factory.createPool(radiateSourceAddress, address(this), 100);
            IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);
        } else {
            flags[14] = true;
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(poolAddress).slot0();

            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);
            }
        }

        v3Pool = IUniswapV3Pool(poolAddress);
    }

    /**
     * @dev Fallback to receive from LP when swapping
     */
    receive() external payable {}

    // =---------- ACL FUNCTIONS (PUBLIC)

    /**
     * @dev Owned function to set all values in the claimants list to 0
     */
    function resetClaimants() public onlyRole(GOVERNOR_ROLE) {
        claimSession += 1;
    }

    /**
     * @dev Allocates debt to debtReserve and removes/adds the yield from radiateSourceHolders (if necessary)
     * requires `flags[3]` = true
     */
    function updateDebt(uint256 _debt) public onlyRole(GOVERNOR_ROLE) {
        require(flags[3], "ERC20Radiate: Allocations are not enabled.");
        require(_debt >= debtSupply_);

        debtReserve = _debt;
    }

    /**
     * @dev Apply income to claims account
     */
    function updateClaimant(uint256 _tokens, address account) public onlyRole(GOVERNOR_ROLE) {
        updateClaims(_tokens, account);
    }

    /**
     * @dev Owned function to restore previously set `claimSession`
     */
    function updateClaimSession(uint256 _session) public onlyRole(GOVERNOR_ROLE) {
        claimSession = _session;
    }

    /**
     * @dev Update claimType to param `type`
     * `type` (0) - Operational claims
     * `type` (1) - Affiliate/referral claims
     */
    function updateClaimType(uint256 _type) public onlyRole(GOVERNOR_ROLE) {
        claimType = _type;
        resetClaimants();
    }

    /**
     * @dev Uniswap path of position liquidation is configurable
     */
    function updateLiquidationPath(address[] memory _path) public onlyRole(GOVERNOR_ROLE) {
        liquidationPath = _path;
    }

    /**
     * @dev Rate limit for network rate allocations
     */
    function updateLiquidityRateLimit(uint256 _value) public onlyRole(GOVERNOR_ROLE) {
        liquidityRateLimit_ = _value;
    }

    /**
     * @dev Minimum payout rate to Radiators is configurable
     */
    function updateMinRate(uint256 _value) public onlyRole(GOVERNOR_ROLE) {
        yieldMinRate_ = _value;
    }

    /**
     * @dev ERC-NNN mutator
     */
    function updateName(string memory param) public onlyRole(GOVERNOR_ROLE) {
        _name = param;
    }

    /**
     * @dev Operation address is configurable
     */
    function updateOperationalAddress(address payable _account, uint8 _index, uint8 _length) public onlyRole(GOVERNOR_ROLE) {
        operationalAddress[_index] = _account;
        operationalLedgerLength = _length;
    }

    /**
     * @dev Defines address with oracle access as `oracle`
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function updateRateOracle(address oracle) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rateOracle = IRateOracle(oracle);

        emit onRateOracleUpdate(oracle);
    }

    /**
     * @dev Uniswap path of yield reconciliation is configurable
     */
    function updateReconciliationPath(address[] memory _path) public onlyRole(GOVERNOR_ROLE) {
        reconciliationPath = _path;

        if (_path.length > 1) {
            flags[10] = true;
        } else {
            flags[10] = false;
        }
    }

    /**
     * @dev Yield bearing token is configurable
     */
    function updateRadiateSourceAddress(address _radiateSourceAddress) public onlyRole(GOVERNOR_ROLE) {
        radiateSourceAddress = payable(_radiateSourceAddress);
        radiateSource = ERC20(radiateSourceAddress);
        radiateSource.approve(__msgSender(), 115792089237316195423570985008687907853269984665640564039457584007913129639935);
    }

    /**
     * @dev Reserve token is configurable
     */
    function updateRadiateTargetAddress(address _radiateTargetAddress) public onlyRole(GOVERNOR_ROLE) {
        /*radiateTargetAddress = payable(_radiateTargetAddress);
        radiateTarget = ERC20Prismatic(radiateTargetAddress);
        radiateTarget.approve(__msgSender(), 115792089237316195423570985008687907853269984665640564039457584007913129639935);*/
    }

    /**
    * @dev The operational rate, which determines how much of the reserve is used
     * for specific operations (marketing/promotions, human resources, et cetra) is configurable.
     * `type` (0) - Operational rate
     * `type` (1) - Network rate
     * `type` (2) - Unwrap rate
     * `type` (3) - Withdrawal rate
     * `type` (4) - Transfer rate
     * `type` (5) - Rebate rate
     * `type` (6) - Allocation rate
     * `type` (7) - Credit rate
     */
    function updateRate(uint256 _type, uint256 _rate) public onlyRole(GOVERNOR_ROLE) {
        systemRates[_type] = _rate;
    }

    /**
     * @dev The operational rate, which determines how much of the reserve is used
     * for specific operations (marketing/promotions, human resources, et cetra) is configurable.
     * `type` (0) - Operational rate
     * `type` (1) - Network rate
     * `type` (2) - Unwrap rate
     * `type` (3) - Withdrawal rate
     * `type` (4) - Transfer rate
     * `type` (5) - Rebate rate
     * `type` (6) - Allocation rate
     * `type` (7) - Credit rate
     */
    function updateRateByAccount(address _account, uint256 _type, uint256 _rate) public onlyRole(GOVERNOR_ROLE) {
        userRates[_type][_account] = _rate;
    }

    /**
     * @dev ERC-NNN mutator
     */
    function updateSymbol(string memory param) public onlyRole(GOVERNOR_ROLE) {
        _symbol = param;
    }

    /**
     * @dev Toggles `flag`
     * `flag` (1) - Yield enabled - Network rates are/aren't allocated to the yield pool
     * `flag` (2) - Unwraps enabled - Holders will/won't have the option to exit
     * `flag` (3) - External allocations enabled - `debtReserve` will/won't be available for pending exchanges
     * `flag` (4) - Claims enabled - Allocated operational rate is accessible
     * `flag` (5) - Transfers enabled - Transfer function is accessible
     * `flag` (6) - Account-based rates enabled - Account-based based rates enabled
     * `flag` (7) - Allocated balance withdraw enabled - Allocationed balances can be withdrawn
     * `flag` (8) - Instant rebate enabled - Purchase based rebates enabled
     * `flag` (9) - Reserve enabled - Rates are/aren't allocated to the reserve pool
     * `flag` (10) - Reconciliation enabled - Withdraw yield is exchanged for reconciliation token
     * `flag` (11) - Oracle enabled - Access to rate oracle helper contract
     * `type` (12) - AMM Rate enabled - Liquidity based network rate calculation enabled
     * `type` (13) - Credit guarantees enabled - Credit limit determinant
     * `type` (14) - LP Pair liquidity enabled - Rely on initial rate for quotes.
     */
    function updateFlags(uint256 _flag, bool _enable) public onlyRole(GOVERNOR_ROLE) {
        if (_flag == 1) {
            require(flags[9] == false);
        }

        if (_flag == 4) {
            if (_enable == false) {
                resetClaimants();
            }
        }

        if (_flag == 9) {
            require(flags[1] == false);
        }

        flags[_flag] = _enable;
    }

    /**
     * @dev Updates treasurerCollection_[] based `action` and `reserveLimit` param
     * {action} - 0 - Disable `_treasurer`
     * {action} - 1 - Enable/Add `_treasurer`
     * {reserveLimit} - Limits `_treasurer` access to debtReserve
     */
    function updateTreasurers(uint256 _action, address _treasurer, uint256 _limit) public onlyRole(GOVERNOR_ROLE) {
        require(_limit <= (debtReserve - debtSupply_));

        if (_action == 1) {
            _grantRole(TREASURER_ROLE, _treasurer);
        } else {
            _revokeRole(TREASURER_ROLE, _treasurer);
        }

        treasurerCollection_[_treasurer].status = _action;

        treasurerCollection_[_treasurer].reserveLimit = _limit;

        treasurerCollection_[_treasurer].contractAddress = _treasurer;
    }

    /**
     * @dev Update yield available to reserve
     */
    function updateYieldBalance(uint256 _supply, uint256 _return) public onlyRole(GOVERNOR_ROLE) {
        yieldSupply_ = _supply;

        yieldReturn_ = _return;

        distribute();
    }

    /**
     * @dev Payout rate to Radiators is configurable
     */
    function updateYieldRate(uint256 _value) public onlyRole(GOVERNOR_ROLE) {
        yieldRate_ = _value;
    }

    // =---------- PUBLIC FUNCTIONS (RADIATE)

    /**
     * @dev Withdraws all of the callers earnings.
     */
    function claim() public onlyClaimants {
        require(flags[4], "ERC20Radiate: Claims are not enabled.");

        uint256 _claims = accountClaims();

        operationalReserve[claimSession] = operationalReserve[claimSession].sub(_claims);

        _mint(__msgSender(), _claims);

        claimsLedger_[claimSession][__msgSender()] = 0;

        // Update account statements
        statementLedger_[__msgSender()].claimed = statementLedger_[__msgSender()].claimed.add(_claims);

        statementLedger_[__msgSender()].claims += 1;

        // Update analytics
        transactions += 1;

        claimed += _claims;

        emit onClaim(__msgSender(), _claims, block.timestamp, claimSession);

        distribute();
    }

    /**
     * @dev Liquidate ERC20Radiate position to {radiateTarget}
     */
    function unwrap(uint256 _amount) public onlyRadiators {
        require(flags[2], "ERC20Radiate: Unwrapping is not enabled.");

        if (flags[7]) {
            require(_amount <= balances_[__msgSender()].add(allocationsTo_[__msgSender()]));
        } else {
            require(_amount <= balances_[__msgSender()].sub(allocationsTo_[__msgSender()]));
        }

        uint256 _rebate;

        if (statementLedger_[__msgSender()].rebated > 0) {
            _rebate = SafeMath.div(statementLedger_[__msgSender()].rebated * magnitude, balances_[__msgSender()]) * _amount;

            statementLedger_[__msgSender()].rebated = statementLedger_[__msgSender()].rebated.sub(_rebate.div(magnitude));
        }

        uint256 _rate = _amount.mul(rateByAccount(__msgSender(), 2)).div(100).div(_base).add(_rebate.div(magnitude));

        allocateRates(_rate);

        uint256 _taxedRadiateShares = _amount.sub(_rate);

        // Reconcile unwrapped tokens with ledgers
        reconcile(_taxedRadiateShares, liquidationPath);

        // Deflate ERC20Radiate token supply
        tokenSupply_ = tokenSupply_.sub(_taxedRadiateShares);

        // Deflate ERC20Radiate share supply
        shareSupply_ = shareSupply_.sub(_taxedRadiateShares);

        // Burn taxed amount
        _burn(__msgSender(), _taxedRadiateShares);

        // Update account statements
        statementLedger_[__msgSender()].withdrawn = statementLedger_[__msgSender()].withdrawn.add(_taxedRadiateShares);

        statementLedger_[__msgSender()].withdrawals += 1;

        // Update analytics
        transactions += 1;

        withdrawn += _taxedRadiateShares;

        // TODO - Ensure supply matches burned amount
        // Deflate account supply
        if (_amount > balances_[__msgSender()]) {
            balances_[__msgSender()] = 0;
        } else {
            balances_[__msgSender()] = balances_[__msgSender()].sub(_amount);
        }

        emit onTokenUnwrap(__msgSender(), _amount, _taxedRadiateShares, block.timestamp);

        distribute();
    }

    /**
     * @dev Recalculate yield and allocate value.
     * value is allocated to `yieldSupply` based on the user's network rate
     */
    function transact() public onlyRole(TRANSACTOR_ROLE) returns (uint256) {
        uint256 time_ = block.timestamp.sub(yieldTimestamp);

        distribute();

        emit onTransact(__msgSender(), time_);

        return time_;
    }

    /**
     * @dev Transfer tokens from the caller to a new holder. Zero rates
     */
    function transfer(address _to, uint256 _amount) public onlyRadiators override returns (bool) {
        require(flags[5], "ERC20Radiate: Transfers are not enabled.");

        require(_amount <= balances_[__msgSender()]);

        _transfer(__msgSender(), _to, _amount);

        return true;
    }

    /**
     * @dev Withdraws all of the callers earnings.
     */
    function withdraw() public onlyRecipients {
        uint256 _yield = accountYield();

        uint256 _rate = _yield.mul(rateByAccount(__msgSender(), 3)).div(100).div(_base);

        allocateRates(_rate);

        uint256 _taxedRadiateYield = _yield.sub(_rate);

        if (yieldSupply_ >= _yield) {
            yieldSupply_ -= _yield;
        } else {
            yieldSupply_ = 0;
        }

        // Reconciliation flag
        if (flags[10] == false) {
            _mint(__msgSender(), _taxedRadiateYield);

            // Update account statements
            statementLedger_[__msgSender()].withdrawn = statementLedger_[__msgSender()].withdrawn.add(_taxedRadiateYield);

            statementLedger_[__msgSender()].withdrawals += 1;

            // Update analytics
            transactions += 1;

            withdrawn += _taxedRadiateYield;

            emit onWithdraw(__msgSender(), _taxedRadiateYield, block.timestamp);
        } else {
            _mint(address(this), _taxedRadiateYield);

            reconcile(_taxedRadiateYield, reconciliationPath);

            // Update account statements
            statementLedger_[__msgSender()].withdrawn = statementLedger_[__msgSender()].withdrawn.add(_taxedRadiateYield);

            statementLedger_[__msgSender()].withdrawals += 1;

            // Update analytics
            transactions += 1;

            withdrawn += _taxedRadiateYield;

            emit onWithdraw(__msgSender(), _taxedRadiateYield, block.timestamp);
        }

        distribute();
    }

    /**
     * @dev Converts all incoming tokens to tokens for the caller, and passes down the referral address
     */
    function wrap(uint256 _amount, address _referrer) public returns (uint256) {
        return wrapFor(__msgSender(), _amount, _referrer);
    }

    /**
     * @dev Converts all incoming tokens to tokens for the caller, and passes down the referral addy (if any)
     */
    function wrapFor(address _address, uint256 _amount, address _referrer) public returns (uint256) {
        if (claimType == 0) {
            updateClaims(_amount, operationalAddress[0]);
        }

        if (claimType == 1) {
            updateClaims(_amount, _referrer);
        }

        if (claimType == 2) {
            for (uint8 index = 0; index < operationalLedgerLength; index++) {
                updateClaims(_amount.div(operationalLedgerLength), operationalAddress[index]);
            }
        }

        require(radiateSource.transferFrom(__msgSender(), address(this), _amount), "ERC20Radiate: Transfer failed.");

        uint256 amount = wrapTokens(_address, _amount);

        emit onTokenWrap(
            _address,
            _amount,
            amount,
            block.timestamp
        );

        distribute();

        return amount;
    }

    // =---------- PUBLIC FUNCTIONS (ERC-NNN)

    /**
     * @dev ERC-NNN accessor
     */
    function allowance(address _owner, address _spender) public view override returns (uint256) {
        return _allowances[_owner][_spender];
    }

    /**
     * @dev ERC-NNN mutator
     */
    function approve(address _spender, uint256 _amount) public override returns (bool) {
        _approve(__msgSender(), _spender, _amount);

        return true;
    }

    /**
     * @dev ERC-NNN mutator
     */
    function burn(uint256 _amount) external {
        shareSupply_ -= _amount;

        _burn(__msgSender(), _amount);
    }

    /**
     * @dev ERC-NNN accessor
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev ERC-NNN mutator (nested)
     */
    // TODO - Ensure access control
    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    /**
     * @dev ERC-NNN accessor
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev ERC-NNN accessor
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev ERC-NNN mutator
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _allowances[_from][__msgSender()] = _allowances[_from][__msgSender()].sub(_amount, "ERC20: transfer amount exceeds allowance.");

        _transfer(__msgSender(), _to, _amount);

        return true;
    }

    // =---------- HELPER FUNCTIONS (PUBLIC)

    /**
     * @dev Retrieve the claims owned by the caller.
     */
    function accountClaims() public view returns (uint256) {
        return claimsOf(__msgSender());
    }

    /**
     * @dev Retrieve the debt owned by the caller.
     */
    function accountDebt() public view returns (uint256) {
        return allocationsOf(__msgSender());
    }

    /**
     * @dev Retrieve the tokens owned by the caller.
     */
    function accountTokens() public view returns (uint256) {
        return balanceOf(__msgSender());
    }

    /**
     * @dev Retrieve the yield owned by the caller.
     */
    function accountYield() public view returns (uint256) {
        return yieldOf(__msgSender());
    }

    /**
     * @dev Retrieve the token balance of any single address.
     */
    function balanceOf(address _caller) public view override returns (uint256) {
        return balances_[_caller];
    }

    /**
     * @dev Retrieve the claims balance of any single address.
     */
    function claimsOf(address _caller) public view returns (uint256) {
        return claimsLedger_[claimSession][_caller].div(claimSupply_[claimSession]).mul(operationalReserve[claimSession]);
    }

    /**
     * @dev Retrieve the debt balance of any single address.
     */
    function allocationsOf(address _caller) public view returns (uint256) {
        return allocationsTo_[_caller];
    }

    /**
     * @dev Retrieve the current supply of debt.
     */
    function yieldPerShare() public view returns (uint256) {
        return yieldPerShare_;
    }

    /**
     * @dev Method to view the current eth stored in the contract
     */
    function radiateBalance() public view returns (uint256) {
        return balanceOf(poolAddress);
    }

    /**
     * @dev Return the rate for `_type`.
     */
    function rate(uint256 _type) public view returns (uint256) {
        return rateByAccount(__msgSender(), _type);
    }

    /**
     * @dev Return the rate for `_account` of `_type`.
     */
    function rateByAccount(address _account, uint256 _type) internal view returns (uint256) {
        if (flags[12] && _type == 1) {
            return getLiquidityRateInverse();
        }

        if (flags[6]) {
            return userRates[_type][_account];
        } else {
            return systemRates[_type];
        }
    }

    /**
     * @dev Retrieve wrapped token share of any signle address.
     */
    function sharesOf(address _caller) public view returns (uint256) {
        return (shareRate(_caller) * shareSupply_);
    }

    /**
     * @dev Statement of any single address
     */
    function statsOf(address _caller) public view returns (uint256[18] memory) {
        Statement memory s = statementLedger_[_caller];

        uint256[18] memory statArray = [
            s.allocated,
            s.claimed,
            s.claims,
            s.deposited,
            s.guaranteed,
            s.liquidated,
            s.liquidations,
            s.allocations,
            s.paid,
            s.rebated,
            s.receipts,
            s.received,
            s.transferred,
            s.transfers,
            s.withdrawals,
            s.withdrawn,
            s.wrapped,
            s.wraps
        ];

        return statArray;
    }

    /**
     * @dev Retrieve wrapped token share of any single address.
     */
    function shareRate(address _caller) public view returns (uint256) {
        if (tokenSupply_ > 0) {
            return (balances_[_caller] * magnitude) / tokenSupply_;
        } else {
            return 0;
        }
    }

    /**
     * @dev Retrieve the yield allocated in contract.
     */
    function totalYield() public view returns (uint256[2] memory) {
        return [yieldSupply_, yieldReturn_];
    }

    /**
     * @dev Retrieve the current supply of debt.
     */
    function totalDebt() public view returns (uint256) {
        return debtSupply_;
    }

    /**
     * @dev Retrieve the total shares locked.
     */
    function totalShares() public view returns (uint256) {
        return shareSupply_;
    }

    /**
     * @dev Retrieve the total token supply.
     */
    function totalSupply() public view override returns (uint256) {
        return tokenSupply_;
    }

    /**
     * @dev Retrieve the yield balance of any single address.
     */
    function yieldOf(address _caller) public view returns (uint256) {
        uint256 _userYield = yieldPerShare_.mul(sharesOf(_caller)).div(magnitude).div(magnitude);

        if (_userYield > statementLedger_[_caller].withdrawn) {
            _userYield = _userYield.sub(statementLedger_[_caller].withdrawn);
        } else {
            return 0;
        }

        if (_userYield > statementLedger_[_caller].guaranteed) {
            return SafeMath.add(statementLedger_[_caller].guaranteed, _userYield.sub(statementLedger_[_caller].guaranteed).mul(yieldMinRate_).div(100).div(_base));
        } else {
            return _userYield;
        }
    }

    /**
     * @dev Retrieve the current supply of debt.
     */
    function yieldRate(address user) public view returns (uint256) {
        if (flags[11]) {
            return rateOracle.getEasingRate(user, radiateSourceAddress, address(this));
        } else {
            uint256 allotted;

            if (flags[13]) {
                allotted = rateByAccount(__msgSender(), 7).mul(statementLedger_[user].deposited).div(_base).div(100);
            } else {
                allotted = statementLedger_[user].guaranteed;
            }

            if (statementLedger_[user].withdrawn >= allotted) {
                return yieldMinRate_;
            }
        }

        return yieldRate_;
    }

    // =---------- HELPERS FUNCTIONS (INTERNAL)

    /**
     * @dev ERC-NNN mutator (nested)
     */
    function _approve(address _owner, address _spender, uint256 _amount) internal override {
        require(_owner != address(0), "ERC20: approve from the zero address.");

        require(_spender != address(0), "ERC20: approve to the zero address.");

        _allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");

        balances_[account] = balances_[account].sub(amount, "ERC20: burn amount exceeds balance");

        tokenSupply_ = tokenSupply_.sub(amount);

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev ERC-NNN mutator (nested)
     */
    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");

        tokenSupply_ = tokenSupply_.add(amount);

        balances_[account] = balances_[account].add(amount);

        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev ERC-NNN mutator (nested)
     */
    function _transfer(address _from, address _to, uint256 _amount) internal override {
        if (accountYield() > 0) {
            withdraw();
        }

        uint256 _rate = _amount.mul(rateByAccount(__msgSender(), 4)).div(100).div(_base);

        allocateRates(_rate);

        uint256 _taxedRadiateShares = _amount.sub(_rate);

        // Perform swap
        balances_[_from] = balances_[_from].sub(_taxedRadiateShares);

        balances_[_to] = balances_[_to].add(_taxedRadiateShares);

        updateUsers(_to);

        // Update account statements
        statementLedger_[_from].transfers += 1;
        statementLedger_[_from].transferred += _taxedRadiateShares;
        statementLedger_[_to].received += _taxedRadiateShares;
        statementLedger_[_to].receipts += 1;

        // Update analytics
        transactions += 1;

        transferred += _taxedRadiateShares;

        emit Transfer(_from, _to, _taxedRadiateShares);
    }

    /**
     * @dev Apply incoming rates to appropriate accounts
     */
    function allocateRates(uint256 incomingRate) internal returns (uint256) {
        uint256 operationalIncome = incomingRate.mul(rateByAccount(__msgSender(), 0)).div(100).div(_base);

        if (flags[15]) {
            (uint256 reserve0, uint256 reserve1) = PoolHelper.getReserves(poolAddress);

            if (reserve0 == 0 || reserve1 == 0) {
                return incomingRate;
            } else {
                incomingRate = incomingRate.mul(uint256(reserve0)).div(uint256(reserve1));
            }
        }

        operationalReserve[claimSession] = operationalReserve[claimSession].add(operationalIncome);

        // Yield pool allocation active
        if (flags[1]) {
            yieldSupply_ = yieldSupply_.add(incomingRate);
            yieldReturn_ = yieldReturn_.add(operationalIncome);
        }

        if (flags[9]) {
            debtReserve = debtReserve.add(incomingRate);

            emit onReserveIncrease(__msgSender(), incomingRate, block.timestamp);
        }

        return yieldSupply_;
    }

    /**
     * @dev Distribute yield balance across held shares
     */
    function distribute() internal {
        if (block.timestamp.sub(yieldTimestamp) > yieldIteration && tokenSupply_ > 0) {
            // Add excess yield to yield balance
            uint256 _excessTokens = yieldSupply_.mul(yieldRate(__msgSender())).div(100).div(_base).div(86400 seconds);

            uint256 yield = _excessTokens * block.timestamp.sub(yieldTimestamp);

            if (yield > 0) {
                if (flags[1]) {
                    yieldSupply_ = yieldSupply_.add(yield);
                    yieldReturn_ = yieldReturn_.add(yield);
                }

                if (flags[9]) {
                    debtReserve = debtReserve.add(yield);

                    emit onReserveIncrease(__msgSender(), yield, block.timestamp);
                }
            }

            yieldTimestamp = block.timestamp;

            updateYieldPerShare();
        }
    }

    /**
     * @dev Returns liquidity rate for {radiateTarget} using inverse.
     */
    function getLiquidityRateInverse() internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = PoolHelper.getReserves(poolAddress);

        if ((uint256(reserve0)).mul(_base).div(uint256(reserve1)) > liquidityRateLimit_) {
            return liquidityRateLimit_;
        }

        return (uint256(reserve0)).mul(_base).div(uint256(reserve1)).mul(100);
    }

    /**
     * @dev Internal function to actually wrap the tokens.
     */
    function wrapTokens(address _receiver, uint256 _tokens) internal returns (uint256) {
        updateUsers(_receiver);

        if (radiateSource.allowance(address(this), liquidityManagerAddress) < _tokens) {
            radiateSource.approve(liquidityManagerAddress, _tokens);
        }

        if (allowance(address(this), liquidityManagerAddress) < _tokens) {
            _approve(address(this), liquidityManagerAddress, _tokens);
        }

        uint256 _taxedRadiateTokens = _tokens;
        uint256 rebate;

        if (flags[14] == false) {
            flags[14] = true;

            // TODO - Add V3 liquidity add function

            liquidityManager.mintNewPosition(address(this), radiateSourceAddress, _taxedRadiateTokens);
            /*addLiquidity(radiateSourceAddress, radiateTargetAddress, _taxedRadiateTokens, targetLiquidity, 0, 0, operationalAddress[0], (block.timestamp + 20 minutes));*/
        } else {
            (uint256 reserve0, uint256 reserve1) = PoolHelper.getReserves(poolAddress);

            // TODO - Add V3 liquidity quotes
            /*
            (uint256 amountOut,,,) = v3Quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: radiateSourceAddress,
                tokenOut: address(this),
                fee: 100,
                amountIn: _tokens,
                sqrtPriceLimitX96: 0
            }));
            */

            /*_taxedRadiateTokens = amountOut;*/

            /*_mint(liquidityManagerAddress, _taxedRadiateTokens);*/

            // TODO - Add V3 liquidity add function
            /*liquidityManager.mintNewPosition(radiateSourceAddress, address(this), _tokens, _taxedRadiateTokens);*/
            /*addLiquidity(radiateSourceAddress, radiateTargetAddress, _tokens, _taxedRadiateTokens, 0, 0, operationalAddress[0], (block.timestamp + 20 minutes));*/

            /*
            if (flags[15]) {
                _taxedRadiateTokens = _taxedRadiateTokens.mul(uint256(reserve0)).div(uint256(reserve1));
            }
            */
        }

        // Instant rebate
        if (flags[8]) {
            /*uint256 rebate = (_tokens.mul(rateByAccount(__msgSender(), 5)).div(100).div(_base));*/

            // Mint rebated tokens to user
            _mint(_receiver, rebate);

            // Update analytics
            rebated += rebate;
            
            statementLedger_[_receiver].rebated += rebate;
        }

        uint256 _rate = _tokens.mul(rateByAccount(__msgSender(), 1)).div(100).div(_base);

        allocateRates(_rate);

        require(_taxedRadiateTokens > 0 && _taxedRadiateTokens.add(tokenSupply_) > tokenSupply_);

        _mint(_receiver, _taxedRadiateTokens);

        shareSupply_ += _taxedRadiateTokens;

        updateYieldPerShare();

        // Update analytics
        deposited += _tokens;
        guaranteed += _taxedRadiateTokens.mul(rateByAccount(__msgSender(), 7)).div(_base).div(100);
        transactions += 1;
        wrapped += _taxedRadiateTokens;

        // Update account statements
        statementLedger_[__msgSender()].deposited += _tokens;
        statementLedger_[__msgSender()].guaranteed += _taxedRadiateTokens.mul(rateByAccount(__msgSender(), 7)).div(_base).div(100);
        statementLedger_[__msgSender()].wrapped += _taxedRadiateTokens;
        statementLedger_[__msgSender()].wraps += 1;

        return _taxedRadiateTokens;
    }

    /**
     * @dev Reconcile withdrawn yield against {reconciliationPath} LP
     */
    function reconcile(uint256 _amount, address[] memory _reconciliationPath) internal returns (uint256) {
        // TODO - Switch code to support V3 router
        /*require(radiateTarget.approve(address(), _amount), "ERC20Radiate: Router approval is required.");*/

        // TODO - Switch code to support V3 swaps
        /*
        swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            _reconciliationPath,
            __msgSender(),
            block.timestamp.add(20 minutes)
        );
        */

        emit onReconciliation(_amount, block.timestamp);

        return _amount;
    }

    /**
     * @dev Apply income to claims account
     */
    function updateClaims(uint256 _tokens, address account) internal {
        claimsLedger_[claimSession][account] += _tokens;

        if (claimSupply_[claimSession] > 0) {
            claimSupply_[claimSession] += _tokens;
        } else {
            claimSupply_[claimSession] = _tokens;
        }
    }

    /**
     * @dev Update yieldPerShare_ variable
     */
    function updateYieldPerShare() internal returns (uint256) {
        yieldPerShare_ = SafeMath.div((yieldReturn_ * magnitude), shareSupply_);

        return yieldPerShare_;
    }

    /**
     * @dev Check if `_user` is active in the ledger, increase user count if not
     */
    function updateUsers(address _user) internal {
        if (statementLedger_[_user].wrapped == 0 && statementLedger_[_user].received == 0) {
            users += 1;

            userRates[0][_user] = systemRates[0];
            userRates[1][_user] = systemRates[1];
            userRates[2][_user] = systemRates[2];
            userRates[3][_user] = systemRates[3];
            userRates[4][_user] = systemRates[4];
            userRates[5][_user] = systemRates[5];
            userRates[6][_user] = systemRates[6];
            userRates[7][_user] = systemRates[7];
        }
    }

    // =---------- EXTERNAL TREASURY FUNCTIONS

    /**
     * @dev Liquifies debt to ERC20Radiate `_amount` is transferred from caller
     */
    function requestAllocationLiquidation(address _borrower, uint256 _amount) external onlyRole(TREASURER_ROLE) {
        require(flags[3], "ERC20Radiate: Allocations are not enabled.");

        if (_amount > allocationsTo_[_borrower]) {
            wrapTokens(_borrower, _amount.sub(allocationsTo_[_borrower]));
        }

        // Move tokens from circulation to reserve
        debtSupply_ = debtSupply_.sub(_amount);

        tokenSupply_ = tokenSupply_.sub(_amount);

        shareSupply_ = shareSupply_.sub(_amount);

        treasurerCollection_[__msgSender()].balanceAllocated -= _amount;

        // Update allocation balances
        allocationsTo_[_borrower] = allocationsTo_[_borrower].sub(_amount);

        _burn(_borrower, _amount);

        updateYieldPerShare();

        // Update account statements
        statementLedger_[_borrower].liquidated += _amount;

        statementLedger_[_borrower].liquidations += 1;

        emit onTokenLiquidation(_borrower, allocationsTo_[_borrower], block.timestamp);

        distribute();
    }

    /**
     * @dev Allows externalTreasurer to allocate supply against `debtReserve`
     */
    function requestExternalAllocation(address _borrower, uint256 _incomingTokens) external onlyRole(TREASURER_ROLE) {
        require(flags[3], "ERC20Radiate: Allocations are not enabled.");

        updateUsers(_borrower);

        uint256 _rate = _incomingTokens.mul(rateByAccount(__msgSender(), 6)).div(100).div(_base);

        allocateRates(_rate);

        uint256 _taxedRadiateTokens = _incomingTokens.sub(_rate);

        emit onTokenAllocation(
            _borrower,
            _incomingTokens,
            _taxedRadiateTokens,
            block.timestamp
        );

        require(_taxedRadiateTokens > 0 && _taxedRadiateTokens.add(tokenSupply_) > tokenSupply_);

        require(_taxedRadiateTokens > 0 && _taxedRadiateTokens.add(treasurerCollection_[__msgSender()].balanceAllocated) <= treasurerCollection_[__msgSender()].reserveLimit);

        require(debtSupply_.add(_taxedRadiateTokens) <= debtReserve);

        _mint(_borrower, _taxedRadiateTokens);
        
        debtSupply_ = debtSupply_.add(_taxedRadiateTokens);

        shareSupply_ += _taxedRadiateTokens;

        treasurerCollection_[__msgSender()].balanceAllocated = treasurerCollection_[__msgSender()].balanceAllocated.add(_taxedRadiateTokens);

        allocationsTo_[_borrower] = allocationsTo_[_borrower].add(_taxedRadiateTokens);

        updateYieldPerShare();

        // Update account statements
        statementLedger_[_borrower].allocated += _incomingTokens;

        statementLedger_[_borrower].allocations += 1;

        transactions += 1;

        allocated += _taxedRadiateTokens;

        distribute();
    }

    /**
     * @dev Returns debt to debtReserve
     */
    function requestExternalDeallocation(address _borrower, uint256 _amount) external onlyRole(TREASURER_ROLE) {
        require(flags[3], "ERC20Radiate: Allocations are not enabled.");

        require(_amount <= allocationsTo_[_borrower], "ERC20Radiate: Cannot overpay debt.");

        require(balanceOf(__msgSender()) >= _amount, "ERC20Radiate: Treasurer account underfunded.");

        // Move tokens from circulation to reserve
        debtSupply_ = debtSupply_.sub(_amount);

        tokenSupply_ = tokenSupply_.sub(_amount);

        shareSupply_ = shareSupply_.sub(_amount);

        treasurerCollection_[__msgSender()].balanceAllocated -= _amount;

        // Update allocation balances
        allocationsTo_[_borrower] = allocationsTo_[_borrower].sub(_amount);

        _burn(_borrower, _amount);

        updateYieldPerShare();

        // Update analytics
        paid += _amount;

        // Update account statements
        statementLedger_[_borrower].paid += _amount;

        emit onTokenConversion(_borrower, _amount, block.timestamp);

        distribute();
    }
}
