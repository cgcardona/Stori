import hre from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  console.log("🚀 TellUrStori V2 - Optimized Contract Deployment");
  console.log("⛓️ Network: TellUrStori L1 (Chain ID: 507)");
  console.log("=" .repeat(60));
  
  try {
    // Get network info
    const network = hre.network;
    const [deployer] = await hre.ethers.getSigners();
    
    console.log("\n📊 Deployment Information:");
    console.log(`├── Network: ${network.name}`);
    console.log(`├── Chain ID: ${network.config.chainId}`);
    console.log(`├── Deployer: ${deployer.address}`);
    
    // Check deployer balance
    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log(`├── Balance: ${hre.ethers.formatEther(balance)} TUS`);
    console.log(`└── Gas Price: ${network.config.gasPrice} wei`);
    
    if (balance === 0n) {
      throw new Error("Deployer has no TUS tokens for gas fees");
    }
    
    console.log("\n🔨 Compiling contracts...");
    await hre.run('compile');
    console.log("✅ Contracts compiled successfully!");
    
    // Deploy TellUrStoriSTEM contract
    console.log("\n📜 Deploying TellUrStoriSTEM contract...");
    const baseMetadataURI = "https://api.tellurstoridaw.com/metadata/";
    
    const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM");
    const stemContract = await TellUrStoriSTEM.deploy(baseMetadataURI);
    await stemContract.waitForDeployment();
    
    const stemAddress = await stemContract.getAddress();
    console.log(`✅ TellUrStoriSTEM deployed to: ${stemAddress}`);
    
    // Deploy STEMMarketplace contract
    console.log("\n🏪 Deploying STEMMarketplace contract...");
    const feeRecipient = deployer.address; // Use deployer as initial fee recipient
    
    const STEMMarketplace = await hre.ethers.getContractFactory("STEMMarketplace");
    const marketplaceContract = await STEMMarketplace.deploy(stemAddress, feeRecipient);
    await marketplaceContract.waitForDeployment();
    
    const marketplaceAddress = await marketplaceContract.getAddress();
    console.log(`✅ STEMMarketplace deployed to: ${marketplaceAddress}`);
    
    // Verify deployment
    console.log("\n🔍 Verifying deployments...");
    
    // Check STEM contract
    const stemName = await stemContract.uri(1).catch(() => "Contract not ready");
    const currentTokenId = await stemContract.getCurrentTokenId();
    console.log(`├── STEM Contract: Token ID counter = ${currentTokenId}`);
    
    // Check marketplace contract
    const marketplaceFee = await marketplaceContract.marketplaceFee();
    const stemContractAddress = await marketplaceContract.stemContract();
    console.log(`├── Marketplace: Fee = ${marketplaceFee} basis points (${marketplaceFee/100}%)`);
    console.log(`└── Marketplace: STEM Contract = ${stemContractAddress}`);
    
    // Save deployment info
    const deploymentInfo = {
      network: network.name,
      chainId: network.config.chainId,
      deployer: deployer.address,
      deployedAt: new Date().toISOString(),
      contracts: {
        TellUrStoriSTEM: {
          address: stemAddress,
          constructorArgs: [baseMetadataURI]
        },
        STEMMarketplace: {
          address: marketplaceAddress,
          constructorArgs: [stemAddress, feeRecipient]
        }
      },
      gasUsed: {
        // Will be populated by actual deployment
      }
    };
    
    // Create deployments directory if it doesn't exist
    const deploymentsDir = path.join(process.cwd(), 'deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    // Save deployment info
    const deploymentFile = path.join(deploymentsDir, `${network.name}-deployment.json`);
    fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
    
    console.log("\n💾 Deployment Information Saved:");
    console.log(`└── File: ${deploymentFile}`);
    
    console.log("\n🎯 Next Steps:");
    console.log("1. ✅ Contracts deployed successfully to TellUrStori L1");
    console.log("2. 🧪 Run comprehensive test suite");
    console.log("3. 🔗 Update indexer service with contract addresses");
    console.log("4. 📱 Update Swift BlockchainClient configuration");
    console.log("5. 🎵 Test end-to-end STEM minting workflow");
    
    console.log("\n🎉 TellUrStori L1 Smart Contracts are LIVE! ⛓️✨");
    console.log("=" .repeat(60));
    
    return {
      stemContract: stemAddress,
      marketplaceContract: marketplaceAddress,
      deployer: deployer.address,
      network: network.name
    };
    
  } catch (error) {
    console.error("\n❌ Deployment failed:");
    console.error(`└── Error: ${error.message}`);
    
    if (error.message.includes("insufficient funds")) {
      console.log("\n💡 Troubleshooting:");
      console.log("├── Check that ewoq account has TUS tokens");
      console.log("├── Verify L1 subnet is running");
      console.log("└── Confirm RPC endpoint is accessible");
    }
    
    process.exit(1);
  }
}

// Execute deployment
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error("💥 Script execution failed:", error);
    process.exit(1);
  });
}

export default main;
