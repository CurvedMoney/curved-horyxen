const Horyxen = artifacts.require("Horyxen");
const LiquidityManager = artifacts.require("LiquidityManager");
const LiquidityEngine = artifacts.require("LiquidityEngine");

// TODO - call grantrole from deploy script

module.exports = async function(deployer) {
  const _radiateSourceAddress = "0xca41f293A32d25c2216bC4B30f5b0Ab61b6ed2CB";
  const _radiateSourceMinterAddress = "0x3a1E7abA44BF21a66344D7A0f795a7DF0B49ED60";
  const _initialRate = BigInt(1e18).toString();
  const _radiatorName = "Horyxen";
  const _radiatorSymbol = "HORYXEN";

  const _liquidityManagerContract = await LiquidityManager.deployed();
  const _liquidityEngineContract = await LiquidityEngine.deployed();

  await deployer.deploy(Horyxen, _radiateSourceAddress, _radiateSourceMinterAddress, _liquidityManagerContract.address, _liquidityEngineContract.address, _initialRate, _radiatorName, _radiatorSymbol);
};