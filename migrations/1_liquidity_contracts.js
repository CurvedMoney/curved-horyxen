const LiquidityManager = artifacts.require("LiquidityManager");

module.exports = async function (deployer) {
    /*const _liquidityContract = await LiquidityManager.deployed();

    if (_liquidityContract) {
        console.log("Liquidity Manager deployed @", _liquidityContract.address);
    } else {
        await deployer.deploy(LiquidityManager);
    }*/

    await deployer.deploy(LiquidityManager);
};
