// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.7.5;

interface ERC20Prismatic {
    /**
     * @dev Returns the address of the current owner.
     */
    function owner() external view returns (address);

    /**
     * @dev Define percentage rate of initial supply to apply to easing.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function setInitialBaseRate(uint256 rate) external;

    /**
     * @dev Assigns `reserve` a `designation` of reserve address based on `type`
     * 
     * `type_` {1} : Define address and designate reserve status of market maker.
     * `type_` {2} : Define address and designate reserve status of treasury.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function setDesignation(address reserve, uint256 type_, bool designation) external;

    /**
     * @dev Defines address with oracle access as `oracle`
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function setRateOracle(address oracle) external;

    /**
     * @dev Defines `agent` as address that receives easing mints from market
     * transactions (buys, sells)
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function setTreasurer(address agent) external;

    /**
     * @dev Defines `agent` as address that receives easing mints from pool
     * transactions (add/remove liquidity)
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function setRepurchaser(address agent) external;

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the supply of tokens used to determine the standard easing
     * advice.
     */
    function initialSupply() external view returns (uint256);

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev {IERC20-transfer} override.  Uses reflected rate to determine percent of
     * `tAmount` that is transferred to `recipient`.
     *
     * Emits a {Transfer} event.
     * 
     * Requirements:
     *
     * - the caller must have a balance of at least `tAmount`.
     */
    function transfer(address recipient, uint256 tAmount) external returns (bool);

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `tAmount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `tAmount`.
     */
    function transferFrom(address sender, address recipient, uint256 tAmount) external returns (bool);

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address account, address spender) external view returns (uint256);

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `tAmount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 tAmount) external returns (bool);

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    /**
     * @dev Returns fellowship status of `account`.
     */
    function isExcludedFromNetworkFee(address account) external view returns (bool);

    /**
     * @dev Returns tax status of `account`.
     */
    function isExcludedFromRate(address account) external view returns (bool);

    /**
     * @dev Returns market maker status of `account`.
     */
    function isMarketMaker(address account) external view returns (bool);

    /**
     * @dev Returns treasury status of `account`.
     */
    function isTreasury(address account) external view returns (bool);

    /**
     * @dev Returns total number of tokens distributed as network fees.
     */
    function totalRates() external view returns (uint256);

    /**
     * @dev Destroys `tAmount` tokens from sender, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` must have at least `tAmount` tokens.
     */
    function burn(uint256 amountOut) external;

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
    function mint(address account, uint256 amountIn) external;

    /**
     * @dev Destroys `tAmount` tokens from sender, reducing the
     * total reflection supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - sender must have at least `tAmount` tokens.
     * - sender cannot be excluded from network rate distribution.
     */
    function reconcile(uint256 tAmount) external;

    /**
     * @dev Returns amount of reflection token received from `tAmount` if 
     * `deductTransferRate` set to {true} rate fees applied to calculation.
     */
    function reflectsToTokens(uint256 tAmount, bool deductTransferRate) external view returns (uint256);

    /**
     * @dev Returns amount of token received from `rAmount`.
     */
    function tokensToReflects(uint256 rAmount) external view returns (uint256);

    /**
     * @dev Defines `account` as address that does not receive reflection tokens.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function excludeFromNetworkFee(address account) external;

    /**
     * @dev Defines `account` as address that does not pay _easingRate on transactions.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function excludeFromRate(address account) external;

    /**
     * @dev Defines `account` as address that pays _easingRate on transactions.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function includeInRate(address account) external;
}
