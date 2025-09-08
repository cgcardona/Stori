import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";

/** @type import('hardhat/config').HardhatUserConfig */
export default {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  networks: {
    tellurstoridaw: {
      type: "http",
      url: "http://127.0.0.1:64815/ext/bc/48tTofoS1HoWcr5ggv2ci8pzuqoZGCoFMetYWcxUEbEHE3x8X/rpc",
      chainId: 507,
      accounts: [
        "0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" // ewoq private key with 1M TUS tokens
      ],
      gasPrice: 25000000000, // 25 gwei
      gas: 8000000,
    },
  },
};