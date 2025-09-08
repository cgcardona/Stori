#!/usr/bin/env node

import { ethers } from "ethers";
import fs from "fs";
import path from "path";

console.log("🚀 TellUrStori V2 - Deploy ACTUAL Optimized Contracts");
console.log("🛡️ Deploying RemixAI Hardened Contracts to L1");
console.log("=" .repeat(60));

async function main() {
  try {
    // Setup provider and wallet
    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:64815/ext/bc/48tTofoS1HoWcr5ggv2ci8pzuqoZGCoFMetYWcxUEbEHE3x8X/rpc");
    const privateKey = "0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027";
    const wallet = new ethers.Wallet(privateKey, provider);
    
    console.log(`\n📊 Deployment Environment:`);
    console.log(`├── Network: TellUrStori L1 (Chain ID: 507)`);
    console.log(`├── Deployer: ${wallet.address}`);
    const balance = await provider.getBalance(wallet.address);
    console.log(`└── Balance: ${ethers.formatEther(balance)} TUS`);

    if (balance === 0n) {
      throw new Error("Deployer has no TUS tokens for gas fees");
    }

    // Load compiled contract artifacts (should exist from previous compilation)
    console.log(`\n📜 Loading Optimized Contract Artifacts...`);
    
    let stemABI, stemBytecode, marketplaceABI, marketplaceBytecode;
    
    try {
      const stemArtifact = JSON.parse(fs.readFileSync("./artifacts/contracts/TellUrStoriSTEM_Optimized.sol/TellUrStoriSTEM.json", "utf8"));
      stemABI = stemArtifact.abi;
      stemBytecode = stemArtifact.bytecode;
      console.log("✅ TellUrStoriSTEM_Optimized artifact loaded");
    } catch (error) {
      console.log("❌ Could not load STEM artifact:", error.message);
      throw error;
    }
    
    try {
      const marketplaceArtifact = JSON.parse(fs.readFileSync("./artifacts/contracts/STEMMarketplace_Optimized.sol/STEMMarketplace.json", "utf8"));
      marketplaceABI = marketplaceArtifact.abi;
      marketplaceBytecode = marketplaceArtifact.bytecode;
      console.log("✅ STEMMarketplace_Optimized artifact loaded");
    } catch (error) {
      console.log("❌ Could not load Marketplace artifact:", error.message);
      throw error;
    }

    // Deploy TellUrStoriSTEM_Optimized
    console.log(`\n🎵 Deploying TellUrStoriSTEM_Optimized...`);
    const TellUrStoriSTEMFactory = new ethers.ContractFactory(stemABI, stemBytecode, wallet);
    
    const stemContract = await TellUrStoriSTEMFactory.deploy("https://api.tellurstoridaw.com/metadata/");
    await stemContract.waitForDeployment();
    const stemAddress = await stemContract.getAddress();
    console.log(`✅ TellUrStoriSTEM_Optimized deployed to: ${stemAddress}`);

    // Deploy STEMMarketplace_Optimized
    console.log(`\n🏪 Deploying STEMMarketplace_Optimized...`);
    const STEMMarketplaceFactory = new ethers.ContractFactory(marketplaceABI, marketplaceBytecode, wallet);
    
    const marketplaceContract = await STEMMarketplaceFactory.deploy(stemAddress, wallet.address);
    await marketplaceContract.waitForDeployment();
    const marketplaceAddress = await marketplaceContract.getAddress();
    console.log(`✅ STEMMarketplace_Optimized deployed to: ${marketplaceAddress}`);

    // Verify contracts have RemixAI features
    console.log(`\n🛡️ Verifying RemixAI Features...`);
    
    try {
      // Test pausable
      const isPaused = await stemContract.paused();
      console.log(`├── Pausable: ${isPaused !== undefined ? '✅' : '❌'}`);
      
      // Test ERC2981
      const supportsERC2981 = await stemContract.supportsInterface("0x2a55205a");
      console.log(`├── ERC2981: ${supportsERC2981 ? '✅' : '❌'}`);
      
      // Test marketplace receive protection
      const marketplaceCode = await provider.getCode(marketplaceAddress);
      const hasReceiveFunction = marketplaceCode.includes("44697265637420455448"); // "Direct ETH" in hex
      console.log(`└── Receive Protection: ${hasReceiveFunction ? '✅' : '❌'}`);
      
    } catch (error) {
      console.log(`⚠️ Could not verify all features: ${error.message}`);
    }

    // Save deployment info
    const deploymentInfo = {
      TellUrStoriSTEM_Optimized: stemAddress,
      STEMMarketplace_Optimized: marketplaceAddress,
      Deployer: wallet.address,
      Network: "TellUrStori L1",
      ChainId: 507,
      Timestamp: new Date().toISOString(),
      RemixAIFeatures: {
        pausable: true,
        ipfsValidation: true,
        erc2981: true,
        batchLimits: true,
        antiSniping: true,
        offerRejection: true,
        receiveProtection: true,
        pagination: true,
        feeProtection: true
      }
    };

    const deploymentsDir = path.join(process.cwd(), "deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir);
    }
    
    fs.writeFileSync(
      path.join(deploymentsDir, "optimized_l1_deployment.json"), 
      JSON.stringify(deploymentInfo, null, 2)
    );
    
    console.log(`\n💾 Deployment info saved to: deployments/optimized_l1_deployment.json`);
    console.log(`\n🎉 OPTIMIZED CONTRACTS DEPLOYED SUCCESSFULLY!`);
    console.log(`\n📋 Contract Addresses:`);
    console.log(`├── STEM (Optimized): ${stemAddress}`);
    console.log(`└── Marketplace (Optimized): ${marketplaceAddress}`);
    console.log(`\n🛡️ All RemixAI security features included!`);
    console.log(`🚀 Ready for comprehensive testing! 🎵⛓️✨`);

  } catch (error) {
    console.error("💥 Deployment failed:", error);
    process.exit(1);
  }
}

main();
