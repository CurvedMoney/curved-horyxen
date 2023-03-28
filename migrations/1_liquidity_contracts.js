const LiquidityManager = artifacts.require("LiquidityManager");

module.exports = async function (deployer) {
    await deployer.deploy(LiquidityManager);
};
