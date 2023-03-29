require("dotenv").config();

const { ETHERSCAN_API, GOERLI_ETHERSCAN_API, MNEMONIC, PROJECT_ID } = process.env;

const HDWalletProvider = require("@truffle/hdwallet-provider");

module.exports = {
    /**
     * Networks define how you connect to your ethereum client and let you set the
     * defaults web3 uses to send transactions. If you don't specify one truffle
     * will spin up a managed Ganache instance for you on port 9545 when you
     * run `develop` or `test`. You can ask a truffle command to use a specific
     * network from the command line, e.g
     *
     * $ truffle test --network <network-name>
     */

    networks: {
        goerli: {
            provider: () => new HDWalletProvider(
                MNEMONIC, `https://goerli.infura.io/v3/${PROJECT_ID}`
            ),
            network_id: 5,
            gasPrice: 10e9,
            skipDryRun: true
        }
    },

    /**
     * Set default mocha options here, use special reporters, etc.
     */

    mocha: {
        // timeout: 100000
    },

    /**
     * Configure your compilers
     */

    compilers: {
        solc: {
            version: "0.7.6",       // Fetch exact version from solc-bin (default: truffle's version)
            docker: false,          // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {
                // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 1
                }
            }
        }
        // Truffle DB is currently disabled by default; to enable it, change enabled:
        // false to enabled: true. The default storage location can also be
        // overridden by specifying the adapter settings, as shown in the commented code below.
        //
        // NOTE: It is not possible to migrate your contracts to truffle DB and you should
        // make a backup of your artifacts to a safe location before enabling this feature.
        //
        // After you backed up your artifacts you can utilize db by running migrate as follows:
        // $ truffle migrate --reset --compile-all
        //
        // db: {
        //   enabled: false,
        //   host: "127.0.0.1",
        //   adapter: {
        //     name: "sqlite",
        //     settings: {
        //       directory: ".db"
        //     }
        //   }
    },

    /**
     * Configure your plugins
     */

    plugins: [
        "truffle-plugin-verify"
    ],

    /**
     * Configure your api keys
     */

    api_keys: {
        etherscan: ETHERSCAN_API,
        goerli_etherscan: GOERLI_ETHERSCAN_API
    },

    /**
     * Configure HTTP proxy
     */

    verify: {
        proxy: {
            host: '127.0.0.1',
            port: '24012'
        }
    }
};
