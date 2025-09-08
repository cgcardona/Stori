#!/usr/bin/env node

import { ethers } from "ethers";
import fs from "fs";

console.log("🏪 TellUrStori V2 - Deploy Marketplace Contract Only");
console.log("🛡️ Deploying STEMMarketplace_Optimized with Proper Nonce Management");
console.log("=" .repeat(70));

// Helper function to add delays between transactions
async function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  try {
    // Setup provider and wallet
    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:49315/ext/bc/2Y2VATbw3jVSeZmZzb4ydyjwbYjzd5xfU4d7UWqPHQ2QEK1mki/rpc");
    const privateKey = "0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027";
    const wallet = new ethers.Wallet(privateKey, provider);
    
    console.log(`\n📊 Deployment Environment:`);
    console.log(`├── Network: TellUrStori L1 (Chain ID: 507)`);
    console.log(`├── Deployer: ${wallet.address}`);
    const balance = await provider.getBalance(wallet.address);
    console.log(`└── Balance: ${ethers.formatEther(balance)} TUS`);

    // Load deployment info
    const deployment = JSON.parse(fs.readFileSync("./deployments/fresh_l1_deployment.json", "utf8"));
    const stemAddress = deployment.TellUrStoriSTEM_Optimized;
    
    console.log(`\n📜 Using Existing STEM Contract:`);
    console.log(`└── STEM Address: ${stemAddress}`);

    // Get current nonce to avoid conflicts
    const currentNonce = await provider.getTransactionCount(wallet.address);
    console.log(`\n🔢 Current Nonce: ${currentNonce}`);

    // Load marketplace contract artifact
    console.log(`\n📄 Loading STEMMarketplace_Optimized Artifact...`);
    const marketplaceArtifact = JSON.parse(fs.readFileSync("./artifacts/contracts/STEMMarketplace_Optimized.sol/STEMMarketplace.json", "utf8"));
    console.log(`✅ STEMMarketplace_Optimized artifact loaded`);

    // Deploy STEMMarketplace_Optimized with explicit nonce
    console.log(`\n🏪 Deploying STEMMarketplace_Optimized...`);
    console.log(`├── STEM Contract: ${stemAddress}`);
    console.log(`├── Fee Recipient: ${wallet.address}`);
    console.log(`└── Using Nonce: ${currentNonce}`);

    const MarketplaceFactory = new ethers.ContractFactory(
      marketplaceArtifact.abi,
      marketplaceArtifact.bytecode,
      wallet
    );

    // Deploy with explicit nonce and higher gas limit
    const marketplace = await MarketplaceFactory.deploy(
      stemAddress,
      wallet.address,
      {
        nonce: currentNonce,
        gasLimit: 8000000,
        gasPrice: ethers.parseUnits("25", "gwei")
      }
    );

    console.log(`⏳ Deployment transaction sent: ${marketplace.deploymentTransaction().hash}`);
    console.log(`⏳ Waiting for deployment confirmation...`);

    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();

    console.log(`✅ STEMMarketplace_Optimized deployed to: ${marketplaceAddress}`);

    // Wait a bit to ensure deployment is fully confirmed
    await delay(5000);

    // Verify deployment by calling a read function
    console.log(`\n🔍 Verifying Deployment...`);
    try {
      const stemContractAddress = await marketplace.stemContract();
      const owner = await marketplace.owner();
      const marketplaceFee = await marketplace.marketplaceFee();
      
      console.log(`├── STEM Contract: ${stemContractAddress}`);
      console.log(`├── Owner: ${owner}`);
      console.log(`└── Marketplace Fee: ${marketplaceFee} basis points`);
      
      if (stemContractAddress.toLowerCase() === stemAddress.toLowerCase()) {
        console.log(`✅ Deployment verification successful!`);
      } else {
        throw new Error("STEM contract address mismatch!");
      }
    } catch (error) {
      console.log(`❌ Deployment verification failed: ${error.message}`);
      throw error;
    }

    // Update deployment info
    deployment.STEMMarketplace_Optimized = marketplaceAddress;
    deployment.Timestamp = new Date().toISOString();
    deployment.MarketplaceDeploymentNonce = currentNonce;

    fs.writeFileSync("./deployments/fresh_l1_deployment.json", JSON.stringify(deployment, null, 2));
    console.log(`\n📄 Updated deployment info: fresh_l1_deployment.json`);

    console.log(`\n🎉 MARKETPLACE DEPLOYMENT COMPLETE! 🏪⛓️✨`);
    console.log(`🚀 Both STEM and Marketplace contracts are now deployed!`);
    console.log(`📊 Ready for comprehensive testing and data population!`);

    // Return deployment info for potential chaining
    return {
      stemAddress,
      marketplaceAddress,
      deployer: wallet.address,
      network: "TellUrStori L1",
      chainId: 507
    };

  } catch (error) {
    console.error("💥 Marketplace deployment failed:", error);
    process.exit(1);
  }
}

main();
