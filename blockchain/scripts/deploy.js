import { ethers } from "ethers";
import hre from "hardhat";
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log("🚀 Deploying TellUrStori V2 Smart Contracts...");
  
  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deploying contracts with account:", deployer.address);
  
  // Get account balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "ETH");
  
  // Deploy TellUrStoriSTEM contract
  console.log("\n📜 Deploying TellUrStoriSTEM contract...");
  const baseMetadataURI = "https://api.tellurstoridaw.com/metadata/";
  
  const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM");
  const stemContract = await TellUrStoriSTEM.deploy(baseMetadataURI);
  await stemContract.waitForDeployment();
  
  const stemAddress = await stemContract.getAddress();
  console.log("✅ TellUrStoriSTEM deployed to:", stemAddress);
  
  // Deploy STEMMarketplace contract
  console.log("\n🏪 Deploying STEMMarketplace contract...");
  const feeRecipient = deployer.address; // Use deployer as fee recipient for now
  
  const STEMMarketplace = await hre.ethers.getContractFactory("STEMMarketplace");
  const marketplaceContract = await STEMMarketplace.deploy(stemAddress, feeRecipient);
  await marketplaceContract.waitForDeployment();
  
  const marketplaceAddress = await marketplaceContract.getAddress();
  console.log("✅ STEMMarketplace deployed to:", marketplaceAddress);
  
  // Verify deployment
  console.log("\n🔍 Verifying deployments...");
  
  // Check STEM contract
  const stemName = await stemContract.uri(1);
  console.log("📋 STEM contract base URI configured");
  
  // Check marketplace contract
  const marketplaceFee = await marketplaceContract.marketplaceFee();
  console.log("📋 Marketplace fee:", marketplaceFee.toString(), "basis points");
  
  // Save deployment info
  const deploymentInfo = {
    network: (await hre.ethers.provider.getNetwork()).name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      TellUrStoriSTEM: {
        address: stemAddress,
        baseMetadataURI: baseMetadataURI
      },
      STEMMarketplace: {
        address: marketplaceAddress,
        feeRecipient: feeRecipient,
        marketplaceFee: marketplaceFee.toString()
      }
    },
    deployedAt: new Date().toISOString()
  };
  
  // Write deployment info to file
  
  const deploymentsDir = path.join(__dirname, '..', 'deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const deploymentFile = path.join(deploymentsDir, `deployment-${Date.now()}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  
  console.log("\n🎉 Deployment completed successfully!");
  console.log("📄 Deployment info saved to:", deploymentFile);
  console.log("\n📋 Contract Addresses:");
  console.log("🎵 TellUrStoriSTEM:", stemAddress);
  console.log("🏪 STEMMarketplace:", marketplaceAddress);
  
  console.log("\n🔧 Next steps:");
  console.log("1. Verify contracts on block explorer");
  console.log("2. Set up indexer service with these addresses");
  console.log("3. Configure frontend with contract addresses");
  console.log("4. Test minting and marketplace functionality");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
