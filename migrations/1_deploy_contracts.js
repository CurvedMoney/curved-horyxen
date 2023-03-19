const Horyxen = artifacts.require("Horyxen");

module.exports = function(deployer) {
  const _radiateSourceAddress = "0x5A055D9249f3ac1a7CDC00b626c8369877DEaB70";
  const _radiateTargetAddress = "0x8A807B32AfF8727072f90819e232A3EEd894b140";
  const _initialRate = BigInt(1e18).toString();
  const _routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  const _radiatorName = "Horyxen";
  const _radiatorSymbol = "HORYXEN";

  deployer.deploy(Horyxen, _radiateSourceAddress, _radiateTargetAddress, _initialRate, _routerAddress, _radiatorName, _radiatorSymbol);
};
