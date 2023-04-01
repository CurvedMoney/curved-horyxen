const Horyxen = artifacts.require("Horyxen");
const LiquidityManager = artifacts.require("LiquidityManager");

module.exports = async function(deployer) {
  const _radiateSourceAddress = "0x5A055D9249f3ac1a7CDC00b626c8369877DEaB70";
  const _initialRate = BigInt(1e18).toString();
  const _radiatorName = "Horyxen";
  const _radiatorSymbol = "HORYXEN";

  const _liquidityContract = await LiquidityManager.deployed();

  await deployer.deploy(Horyxen, _radiateSourceAddress, _liquidityContract.address, _initialRate, _radiatorName, _radiatorSymbol);
};
