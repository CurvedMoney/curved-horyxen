// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

import "./curved/ERC20Radiate.sol";

contract Horyxen is ERC20Radiate {
     constructor(address _radiateSourceAddress, address _liquidityManagerAddress, address _liquidityEngineAddress, uint256 _initialRate, string memory _radiatorName, string memory _radiatorSymbol) ERC20Radiate(_radiateSourceAddress, _liquidityManagerAddress, _liquidityEngineAddress, _initialRate, _radiatorName, _radiatorSymbol) { }
}
