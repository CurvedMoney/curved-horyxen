const Horyxen = artifacts.require("Horyxen");
const LiquidityManager = artifacts.require("LiquidityManager");

module.exports = async function(deployer) {
  const _radiateSourceAddress = "0x5A055D9249f3ac1a7CDC00b626c8369877DEaB70";
  const _radiateTargetAddress = "0x8A807B32AfF8727072f90819e232A3EEd894b140";
  const _initialRate = BigInt(1e18).toString();
  const _radiatorName = "Horyxen";
  const _radiatorSymbol = "HORYXEN";
  const _factory = "";
  const _WETH = "";

  deployer.deploy(LiquidityManager);
  
  const liquidityContract = await LiquidityManager.deployed();

  deployer.deploy(Horyxen, _radiateSourceAddress, _radiateTargetAddress, liquidityContract.address, _initialRate, _radiatorName, _radiatorSymbol);
};
