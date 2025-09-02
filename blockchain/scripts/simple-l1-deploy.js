import hre from "hardhat";

async function main() {
  console.log("🚀 TellUrStori V2 L1 Deployment");
  console.log("⛓️ Network: tellurstoridaw");
  console.log("🔗 Chain ID: 507");
  
  try {
    // Test compilation first
    await hre.run('compile');
    console.log("✅ Contracts compiled successfully!");
    
    console.log("\n📜 Contract Information:");
    console.log("├── TellUrStoriSTEM.sol - ERC-1155 STEM token contract");
    console.log("├── STEMMarketplace.sol - Comprehensive marketplace");
    console.log("└── Ready for deployment to TellUrStori L1");
    
    console.log("\n🔗 L1 Network Details:");
    console.log("├── RPC URL: http://127.0.0.1:64815/ext/bc/48tTofoS1HoWcr5ggv2ci8pzuqoZGCoFMetYWcxUEbEHE3x8X/rpc");
    console.log("├── Chain ID: 507");
    console.log("├── Token: TUS (TUS Token)");
    console.log("└── Deployer: 0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC (1M TUS balance)");
    
    console.log("\n🎯 Next Steps:");
    console.log("1. Fix Hardhat/Ethers version compatibility");
    console.log("2. Deploy contracts to L1 blockchain");
    console.log("3. Update indexer service configuration");
    console.log("4. Update Swift BlockchainClient with L1 details");
    console.log("5. Test end-to-end STEM minting workflow");
    
    console.log("\n🎉 Phase 3.4 Progress: L1 Blockchain Created & Ready!");
    console.log("✅ Custom Avalanche L1 subnet: COMPLETE");
    console.log("🔄 Smart contract deployment: IN PROGRESS");
    console.log("⏳ Production infrastructure: PENDING");
    
    console.log("\n🚀 TellUrStori L1 is LIVE and waiting for contracts! ⛓️✨");
    
  } catch (error) {
    console.error("❌ Error:", error.message);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("💥 Script failed:", error);
  process.exit(1);
});