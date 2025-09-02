import hre from "hardhat";
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log("🚀 TellUrStori V2 - Deploying to Custom L1 Blockchain");
  console.log("⛓️ Network:", hre.network.name || "tellurstoridaw");
  
  // Get network info safely
  const networkConfig = hre.network.config || {};
  const chainId = networkConfig.chainId || 507;
  console.log("🔗 Chain ID:", chainId);
  
  try {
    // Get deployer account
    const signers = await hre.ethers.getSigners();
    const deployer = signers[0];
    console.log("📝 Deploying with account:", deployer.address);
    
    // Get account balance
    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", hre.ethers.formatEther(balance), "TUS");
    
    // Deploy TellUrStoriSTEM contract
    console.log("\n📜 Deploying TellUrStoriSTEM contract...");
    const baseMetadataURI = "https://api.tellurstoridaw.com/metadata/";
    
    const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM");
    console.log("🔨 Contract factory created");
    
    const stemContract = await TellUrStoriSTEM.deploy(baseMetadataURI);
    console.log("📤 Deployment transaction sent");
    
    await stemContract.waitForDeployment();
    const stemAddress = await stemContract.getAddress();
    
    console.log("✅ TellUrStoriSTEM deployed to:", stemAddress);
    
    // Deploy STEMMarketplace contract
    console.log("\n🏪 Deploying STEMMarketplace contract...");
    const STEMMarketplace = await hre.ethers.getContractFactory("STEMMarketplace");
    const marketplaceContract = await STEMMarketplace.deploy(stemAddress);
    await marketplaceContract.waitForDeployment();
    
    const marketplaceAddress = await marketplaceContract.getAddress();
    console.log("✅ STEMMarketplace deployed to:", marketplaceAddress);
    
    // Set marketplace approval on STEM contract
    console.log("\n🔗 Setting marketplace approval...");
    const approveTx = await stemContract.setApprovalForAll(marketplaceAddress, true);
    await approveTx.wait();
    console.log("✅ Marketplace approved for STEM operations");
    
    // Save deployment info
    const deploymentInfo = {
      network: hre.network.name || "tellurstoridaw",
      chainId: chainId,
      deployer: deployer.address,
      contracts: {
        TellUrStoriSTEM: {
          address: stemAddress,
          constructorArgs: [baseMetadataURI]
        },
        STEMMarketplace: {
          address: marketplaceAddress,
          constructorArgs: [stemAddress]
        }
      },
      rpcUrl: networkConfig.url || "http://127.0.0.1:64815/ext/bc/48tTofoS1HoWcr5ggv2ci8pzuqoZGCoFMetYWcxUEbEHE3x8X/rpc",
      deployedAt: new Date().toISOString(),
      gasUsed: {
        stemContract: "Estimated ~2.5M gas",
        marketplaceContract: "Estimated ~3.2M gas"
      }
    };
    
    const deploymentsDir = path.join(__dirname, '..', 'deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const deploymentFile = path.join(deploymentsDir, `${hre.network.name}.json`);
    fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
    
    console.log("\n🎉 DEPLOYMENT COMPLETE!");
    console.log("📋 Deployment Summary:");
    console.log("├── Network:", hre.network.name || "tellurstoridaw");
    console.log("├── Chain ID:", chainId);
    console.log("├── RPC URL:", networkConfig.url || "http://127.0.0.1:64815/ext/bc/48tTofoS1HoWcr5ggv2ci8pzuqoZGCoFMetYWcxUEbEHE3x8X/rpc");
    console.log("├── TellUrStoriSTEM:", stemAddress);
    console.log("├── STEMMarketplace:", marketplaceAddress);
    console.log("└── Deployment file:", deploymentFile);
    
    console.log("\n🔧 Next Steps:");
    console.log("1. Update indexer service with new contract addresses");
    console.log("2. Update Swift BlockchainClient with L1 RPC URL");
    console.log("3. Test contract interactions");
    console.log("4. Start indexer service for event monitoring");
    
    console.log("\n🎵 TellUrStori V2 L1 is LIVE! Ready for STEM minting! 🚀⛓️✨");
    
  } catch (error) {
    console.error("❌ Deployment failed:", error.message);
    if (error.reason) {
      console.error("📝 Reason:", error.reason);
    }
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("💥 Deployment script failed:", error);
  process.exit(1);
});