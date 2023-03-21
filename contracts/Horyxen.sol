// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

import "./curved/ERC20Radiate.sol";

contract Horyxen is ERC20Radiate {
     constructor(address _radiateSourceAddress, address _radiateTargetAddress, uint256 _initialRate, address _liquidityManagerAddress, string memory _radiatorName, string memory _radiatorSymbol) ERC20Radiate(_radiateSourceAddress, _radiateTargetAddress, _initialRate, _liquidityManagerAddress, _radiatorName, _radiatorSymbol) { }
}