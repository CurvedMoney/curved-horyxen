const Horyxen = artifacts.require("Horyxen");
const LiquidityManager = artifacts.require("LiquidityManager");

// call grantrole from deploy script

module.exports = async function(deployer) {
  const _radiateSourceAddress = "0xca41f293A32d25c2216bC4B30f5b0Ab61b6ed2CB";
  const _initialRate = BigInt(1e18).toString();
  const _radiatorName = "Horyxen";
  const _radiatorSymbol = "HORYXEN";

  const _liquidityContract = await LiquidityManager.deployed();

  await deployer.deploy(Horyxen, _radiateSourceAddress, _liquidityContract.address, _initialRate, _radiatorName, _radiatorSymbol);
};
