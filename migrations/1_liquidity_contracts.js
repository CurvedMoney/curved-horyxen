const LiquidityManager = artifacts.require("LiquidityManager");
const LiquidityEngine = artifacts.require("LiquidityEngine");

module.exports = async function (deployer) {
    const _liquidityTargetAddress = "0xca41f293A32d25c2216bC4B30f5b0Ab61b6ed2CB";
    const _liquidityTargetMinterAddress = "0x3a1E7abA44BF21a66344D7A0f795a7DF0B49ED60";

    /*
    const _liquidityContract = await LiquidityManager.deployed();

    if (_liquidityContract) {
        console.log("\tLiquidity Manager deployed @", _liquidityContract.address, "\n\n");
    } else {
        await deployer.deploy(LiquidityManager);
    }
    */

    await deployer.deploy(LiquidityManager);
    await deployer.deploy(LiquidityEngine, _liquidityTargetAddress, _liquidityTargetMinterAddress);
};
