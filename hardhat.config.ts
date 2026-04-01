import { existsSync } from "fs";
import { loadEnvFile } from "process";

if (existsSync(".env")) {
  loadEnvFile();
}

import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatEthersChaiMatchers from "@nomicfoundation/hardhat-ethers-chai-matchers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatNetworkHelpers from "@nomicfoundation/hardhat-network-helpers";
import hardhatTypechain from "@nomicfoundation/hardhat-typechain";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

import type { HardhatUserConfig } from "hardhat/config";

function normalizePrivateKey(value: string | undefined): string | undefined {
  if (value === undefined || value.trim() === "") {
    return undefined;
  }

  return value.startsWith("0x") ? value : `0x${value}`;
}

const deployerKey = normalizePrivateKey(process.env.DEPLOYER_KEY);

const networks: NonNullable<HardhatUserConfig["networks"]> = {
  hardhat: {
    type: "edr-simulated", // <-- for the built-in Hardhat network
    chainId: 31337,
    initialBaseFeePerGas: 0,
  },
  localhost: {
    type: "http", // for a local node via RPC
    url: process.env.LOCAL_RPC_URL ?? "http://127.0.0.1:8545",
    chainId: 31337,
  },
};

if (process.env.SEPOLIA_RPC_URL) {
  networks.sepolia = {
    type: "http",
    url: process.env.SEPOLIA_RPC_URL,
    chainId: 11155111,
    accounts: deployerKey ? [deployerKey] : [],
  };
}

const config: HardhatUserConfig = {
  paths: {
    sources: "./examples/contracts",
    tests: "./examples/test_examples",
  },
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "prague",
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  networks,
  verify: {
    etherscan: process.env.ETHERSCAN_API_KEY
      ? {
          enabled: true,
          apiKey: process.env.ETHERSCAN_API_KEY,
        }
      : {
          enabled: false,
        },
  },
 
  plugins: [
    hardhatEthers,
    hardhatTypechain,
    hardhatMocha,
    hardhatEthersChaiMatchers,
    hardhatNetworkHelpers,
    hardhatVerify,
  ],
};

export default config;
