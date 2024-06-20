import * as dotenv from "dotenv";
import { ProxyAgent, setGlobalDispatcher } from "undici";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-vyper";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import * as tenderly from "@tenderly/hardhat-tenderly";

tenderly.setup({ automaticVerifications: true });
dotenv.config();

if (process.env.PROXY) {
  const proxyAgent = new ProxyAgent(process.env.PROXY);
  setGlobalDispatcher(proxyAgent);
}

const accounts = process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [];

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "istanbul",
        },
      }
    ],
  },
  vyper: {
    compilers: [{ version: "0.3.1" }, { version: "0.2.7" }],
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_URL || "https://rpc.sepolia.org",
      chainId: 11155111,
      accounts: [process.env.PRIVATE_KEY_MAINNET!],
    },
    fuji: {
      url: process.env.FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc",
      chainId: 43113,
      accounts: [process.env.PRIVATE_KEY_MAINNET!],
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL || "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: [process.env.PRIVATE_KEY_MAINNET!],
    },
    virtual_avalanche_c_chain: {
      url: "https://virtual.avalanche.rpc.tenderly.co/70448814-5ce2-41b8-af6a-d1b1edcd394f",
      chainId: 434343114,
    },
  },
  tenderly: {
    // https://docs.tenderly.co/account/projects/account-project-slug
    project: "project",
    username: "solomonNSI",
  },
  typechain: {
    outDir: "./scripts/@types",
    target: "ethers-v6",
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      snowtrace: "snowtrace", // apiKey is not required, just set a placeholder
    },
    customChains: [
      {
        network: "snowtrace",
        chainId: 43114,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan",
          browserURL: "https://avalanche.routescan.io"
        }
      }
    ]
  },
  sourcify: {
    enabled: false,
  },
  mocha: {
    timeout: 400000,
  },
};

export default config;
