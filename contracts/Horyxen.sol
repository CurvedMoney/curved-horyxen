// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./curved/ERC20Radiate.sol";

/// @custom:security-contact info@curved.money
contract Horyxen is ERC20Radiate {
     constructor(address _radiateSourceAddress, address _radiateTargetAddress, uint256 _initialRate, address _routerAddress, string memory _radiatorName, string memory _radiatorSymbol) ERC20Radiate(_radiateSourceAddress, _radiateTargetAddress, _initialRate, _routerAddress, _radiatorName, _radiatorSymbol) { }
}