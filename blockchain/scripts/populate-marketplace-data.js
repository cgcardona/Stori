#!/usr/bin/env node

import { ethers } from "ethers";
import fs from "fs";

console.log("🎵 TellUrStori V2 - Marketplace Data Population");
console.log("🚀 Creating Realistic STEM Tokens & Trading Activity");
console.log("=" .repeat(80));

// Realistic STEM data for marketplace population
const STEM_TEMPLATES = [
  // Electronic/EDM
  { name: "Epic Bass Drop", genre: "Electronic", tags: ["bass", "electronic"], duration: 45, royalty: 250, price: "2.5" },
  { name: "Synthwave Melody", genre: "Synthwave", tags: ["melody", "synthwave"], duration: 62, royalty: 180, price: "1.8" },
  { name: "Future Bass Lead", genre: "Electronic", tags: ["future", "bass", "lead"], duration: 38, royalty: 300, price: "3.2" },
  { name: "Ambient Soundscape", genre: "Ambient", tags: ["harmony", "ambient"], duration: 120, royalty: 200, price: "2.0" },
  { name: "Trap Drums", genre: "Trap", tags: ["drums", "trap"], duration: 30, royalty: 120, price: "1.2" },
  
  // Hip Hop
  { name: "Lo-Fi Hip Hop Beat", genre: "Hip Hop", tags: ["drums", "hip hop"], duration: 90, royalty: 75, price: "0.75" },
  { name: "Boom Bap Drums", genre: "Hip Hop", tags: ["drums", "boom bap"], duration: 60, royalty: 150, price: "1.5" },
  { name: "Jazz Hip Hop Loop", genre: "Hip Hop", tags: ["jazz", "loop"], duration: 48, royalty: 200, price: "2.2" },
  
  // Rock/Alternative
  { name: "Rock Guitar Riff", genre: "Rock", tags: ["melody", "rock"], duration: 25, royalty: 210, price: "2.1" },
  { name: "Indie Guitar Melody", genre: "Alternative", tags: ["guitar", "indie"], duration: 55, royalty: 180, price: "1.9" },
  { name: "Punk Bass Line", genre: "Rock", tags: ["bass", "punk"], duration: 35, royalty: 160, price: "1.6" },
  
  // Pop/Commercial
  { name: "Pop Vocal Harmony", genre: "Pop", tags: ["vocals", "harmony"], duration: 50, royalty: 500, price: "5.0" },
  { name: "Commercial Jingle", genre: "Pop", tags: ["commercial", "catchy"], duration: 15, royalty: 800, price: "8.0" },
  { name: "Radio Hook", genre: "Pop", tags: ["hook", "radio"], duration: 20, royalty: 600, price: "6.0" },
  
  // Experimental/Unique
  { name: "Glitch Percussion", genre: "Experimental", tags: ["glitch", "percussion"], duration: 42, royalty: 250, price: "2.8" },
  { name: "Orchestral Strings", genre: "Classical", tags: ["strings", "orchestral"], duration: 75, royalty: 400, price: "4.2" },
  { name: "Ethnic Flute", genre: "World", tags: ["flute", "ethnic"], duration: 65, royalty: 300, price: "3.5" },
  
  // More variety for rich marketplace
  { name: "Minimal Techno Loop", genre: "Electronic", tags: ["minimal", "techno"], duration: 32, royalty: 180, price: "1.7" },
  { name: "Reggae Guitar Skank", genre: "Reggae", tags: ["guitar", "reggae"], duration: 40, royalty: 220, price: "2.3" },
  { name: "Country Banjo", genre: "Country", tags: ["banjo", "country"], duration: 35, royalty: 190, price: "1.95" },
  { name: "Latin Percussion", genre: "Latin", tags: ["percussion", "latin"], duration: 45, royalty: 240, price: "2.6" },
];

// Generate realistic creator addresses (simulate different artists)
const CREATORS = [
  "0x1234567890123456789012345678901234567890",
  "0x2345678901234567890123456789012345678901", 
  "0x3456789012345678901234567890123456789012",
  "0x4567890123456789012345678901234567890123",
  "0x5678901234567890123456789012345678901234",
  "0x6789012345678901234567890123456789012345",
  "0x7890123456789012345678901234567890123456",
  "0x8901234567890123456789012345678901234567",
];

// Helper function to add delays between transactions
async function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Helper function to wait for transaction and add buffer
async function waitForTx(tx, delayMs = 3000) {
  console.log(`   ⏳ Waiting for tx: ${tx.hash.slice(0, 10)}...`);
  const receipt = await tx.wait();
  await delay(delayMs); // Add buffer to prevent nonce conflicts
  return receipt;
}

// Generate random variation for realistic data
function randomVariation(base, variance = 0.2) {
  const variation = 1 + (Math.random() - 0.5) * variance;
  return Math.max(0.1, base * variation);
}

async function main() {
  try {
    // Setup provider and wallet
    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:49315/ext/bc/2Y2VATbw3jVSeZmZzb4ydyjwbYjzd5xfU4d7UWqPHQ2QEK1mki/rpc");
    const privateKey = "0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027";
    const wallet = new ethers.Wallet(privateKey, provider);
    
    console.log(`\n📊 Environment Setup:`);
    console.log(`├── Network: TellUrStori L1 (Chain ID: 507)`);
    console.log(`├── Deployer: ${wallet.address}`);
    const balance = await provider.getBalance(wallet.address);
    console.log(`└── Balance: ${ethers.formatEther(balance)} TUS`);

    // Load deployment info
    const deployment = JSON.parse(fs.readFileSync("./deployments/fresh_l1_deployment.json", "utf8"));
    console.log(`\n📜 Using Deployed STEM Contract:`);
    console.log(`└── Address: ${deployment.TellUrStoriSTEM_Optimized}`);

    // Load contract ABI and create contract instance
    const stemABI = JSON.parse(fs.readFileSync("./artifacts/contracts/TellUrStoriSTEM_Optimized.sol/TellUrStoriSTEM.json", "utf8")).abi;
    const stemContract = new ethers.Contract(deployment.TellUrStoriSTEM_Optimized, stemABI, wallet);

    console.log(`\n🎵 Starting Marketplace Data Population...`);
    console.log(`📊 Creating ${STEM_TEMPLATES.length} diverse STEM tokens`);

    const createdTokens = [];
    let tokenCounter = 1;

    // Phase 1: Create diverse STEM tokens
    console.log(`\n📄 PHASE 1: Creating Diverse STEM Tokens`);
    console.log("-".repeat(60));

    for (const template of STEM_TEMPLATES) {
      try {
        // Add realistic variation to each token
        const supply = Math.floor(randomVariation(15, 0.6)); // 5-25 tokens
        const duration = Math.floor(randomVariation(template.duration, 0.3));
        const royalty = Math.floor(randomVariation(template.royalty, 0.2));
        
        // Use different creators for variety
        const creatorIndex = tokenCounter % CREATORS.length;
        const creator = CREATORS[creatorIndex];
        
        const metadata = {
          name: template.name,
          description: `Professional ${template.genre} STEM for music production. High-quality ${template.tags.join(', ')} element perfect for your tracks.`,
          audioIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG", // Valid IPFS hash
          imageIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG", // Valid IPFS hash
          creator: creator,
          createdAt: Math.floor(Date.now() / 1000) - Math.floor(Math.random() * 86400 * 30), // Random within last 30 days
          duration: duration,
          genre: template.genre,
          tags: template.tags,
          royaltyPercentage: royalty
        };

        console.log(`🎵 [${tokenCounter}/${STEM_TEMPLATES.length}] Creating "${template.name}"`);
        console.log(`   ├── Supply: ${supply} tokens`);
        console.log(`   ├── Genre: ${template.genre}`);
        console.log(`   ├── Duration: ${duration}s`);
        console.log(`   ├── Royalty: ${(royalty/100).toFixed(1)}%`);
        console.log(`   └── Creator: ${creator.slice(0, 8)}...`);

        const tx = await stemContract.mintSTEM(wallet.address, supply, metadata, "0x");
        await waitForTx(tx);

        // Store token info for later phases
        createdTokens.push({
          tokenId: tokenCounter,
          name: template.name,
          genre: template.genre,
          supply: supply,
          price: template.price,
          creator: creator,
          tags: template.tags
        });

        console.log(`   ✅ Token ${tokenCounter} created successfully!`);
        tokenCounter++;

      } catch (error) {
        console.log(`   ❌ Failed to create "${template.name}": ${error.message}`);
      }
    }

    // Phase 2: Create some transfers to simulate trading history
    console.log(`\n📄 PHASE 2: Simulating Trading Activity`);
    console.log("-".repeat(60));

    // Create some random transfers to simulate marketplace activity
    const numTransfers = Math.min(10, createdTokens.length);
    for (let i = 0; i < numTransfers; i++) {
      try {
        const token = createdTokens[Math.floor(Math.random() * createdTokens.length)];
        const recipient = CREATORS[Math.floor(Math.random() * CREATORS.length)];
        const transferAmount = Math.min(3, Math.floor(token.supply / 3)); // Transfer up to 1/3 of supply

        if (transferAmount > 0) {
          console.log(`🔄 [${i+1}/${numTransfers}] Transferring ${transferAmount} of "${token.name}" to ${recipient.slice(0, 8)}...`);
          
          const tx = await stemContract.safeTransferFrom(
            wallet.address, 
            recipient, 
            token.tokenId, 
            transferAmount, 
            "0x"
          );
          await waitForTx(tx);
          console.log(`   ✅ Transfer completed!`);
        }
      } catch (error) {
        console.log(`   ❌ Transfer failed: ${error.message}`);
      }
    }

    // Phase 3: Generate summary statistics
    console.log(`\n📄 PHASE 3: Marketplace Summary`);
    console.log("-".repeat(60));

    const totalTokens = createdTokens.length;
    const totalSupply = createdTokens.reduce((sum, token) => sum + token.supply, 0);
    const avgPrice = createdTokens.reduce((sum, token) => sum + parseFloat(token.price), 0) / totalTokens;
    const genres = [...new Set(createdTokens.map(token => token.genre))];
    const totalVolume = createdTokens.reduce((sum, token) => sum + (parseFloat(token.price) * token.supply), 0);

    console.log(`📊 Marketplace Statistics:`);
    console.log(`├── Total STEM Types: ${totalTokens}`);
    console.log(`├── Total Token Supply: ${totalSupply}`);
    console.log(`├── Average Price: ${avgPrice.toFixed(2)} AVAX`);
    console.log(`├── Total Market Value: ${totalVolume.toFixed(1)} AVAX`);
    console.log(`├── Unique Genres: ${genres.length}`);
    console.log(`└── Genres: ${genres.join(', ')}`);

    // Save marketplace data for frontend integration
    const marketplaceData = {
      timestamp: new Date().toISOString(),
      network: "TellUrStori L1",
      contract: deployment.TellUrStoriSTEM_Optimized,
      tokens: createdTokens,
      statistics: {
        totalTokens,
        totalSupply,
        avgPrice,
        totalVolume,
        genres,
        creators: CREATORS.length
      },
      sampleData: {
        recentActivity: createdTokens.slice(0, 5).map(token => ({
          type: "mint",
          tokenName: token.name,
          creator: token.creator,
          amount: token.supply,
          timestamp: Date.now() - Math.random() * 86400000 * 7 // Random within last week
        })),
        topGenres: genres.slice(0, 5),
        floorPrices: createdTokens.reduce((acc, token) => {
          acc[token.genre] = Math.min(acc[token.genre] || Infinity, parseFloat(token.price));
          return acc;
        }, {})
      }
    };

    fs.writeFileSync('marketplace-data.json', JSON.stringify(marketplaceData, null, 2));
    console.log(`\n📄 Marketplace data saved to: marketplace-data.json`);

    console.log(`\n🎉 MARKETPLACE POPULATION COMPLETE! 🎵⛓️✨`);
    console.log(`🚀 Your blockchain now has rich, realistic STEM marketplace data!`);
    console.log(`📊 Ready for frontend integration with indexer service!`);

  } catch (error) {
    console.error("💥 Marketplace population failed:", error);
    process.exit(1);
  }
}

main();
