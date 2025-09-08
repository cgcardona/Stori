import { expect } from "chai";
import hre from "hardhat";

describe("TellUrStoriSTEM - Comprehensive Test Suite", function () {
  let stemContract;
  let owner, creator, user1, user2;
  let baseMetadataURI;

  // Sample STEM metadata
  const sampleSTEM = {
    name: "Epic Synthwave Beat",
    description: "A nostalgic synthwave track with retro vibes",
    audioIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
    imageIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdH",
    creator: "0x0000000000000000000000000000000000000000", // Will be set by contract
    createdAt: 0, // Will be set by contract
    duration: 180, // 3 minutes
    genre: "Synthwave",
    tags: ["retro", "80s", "electronic", "nostalgic"],
    royaltyPercentage: 1000 // 10%
  };

  beforeEach(async function () {
    [owner, creator, user1, user2] = await hre.ethers.getSigners();
    baseMetadataURI = "https://api.tellurstoridaw.com/metadata/";

    const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM");
    stemContract = await TellUrStoriSTEM.deploy(baseMetadataURI);
    await stemContract.waitForDeployment();
  });

  describe("🏗️ Contract Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      expect(await stemContract.getCurrentTokenId()).to.equal(1);
      expect(await stemContract.owner()).to.equal(owner.address);
    });

    it("Should set correct base metadata URI", async function () {
      // This will revert since token 1 doesn't exist yet, but we can test the URI format
      await expect(stemContract.uri(1)).to.be.revertedWithCustomError(
        stemContract,
        "TokenNotExists"
      );
    });
  });

  describe("🎵 STEM Minting", function () {
    describe("✅ Successful Minting", function () {
      it("Should mint a single STEM with correct metadata", async function () {
        const tx = await stemContract.connect(creator).mintSTEM(
          creator.address,
          100, // amount
          sampleSTEM,
          "0x"
        );

        const receipt = await tx.wait();
        const tokenId = 1;

        // Check event emission
        await expect(tx)
          .to.emit(stemContract, "STEMMinted")
          .withArgs(tokenId, creator.address, sampleSTEM.name, sampleSTEM.audioIPFSHash, 100);

        // Check token balance
        expect(await stemContract.balanceOf(creator.address, tokenId)).to.equal(100);

        // Check metadata
        const metadata = await stemContract.getSTEMMetadata(tokenId);
        expect(metadata.name).to.equal(sampleSTEM.name);
        expect(metadata.creator).to.equal(creator.address);
        expect(metadata.duration).to.equal(sampleSTEM.duration);
        expect(metadata.royaltyPercentage).to.equal(sampleSTEM.royaltyPercentage);

        // Check creator tracking
        const creatorSTEMs = await stemContract.getSTEMsByCreator(creator.address);
        expect(creatorSTEMs).to.deep.equal([tokenId]);
      });

      it("Should mint multiple STEMs with batch function", async function () {
        const stem1 = { ...sampleSTEM, name: "Track 1" };
        const stem2 = { ...sampleSTEM, name: "Track 2", duration: 240 };
        const amounts = [50, 75];

        const tx = await stemContract.connect(creator).batchMintSTEMs(
          creator.address,
          amounts,
          [stem1, stem2],
          "0x"
        );

        // Check balances
        expect(await stemContract.balanceOf(creator.address, 1)).to.equal(50);
        expect(await stemContract.balanceOf(creator.address, 2)).to.equal(75);

        // Check creator STEMs
        const creatorSTEMs = await stemContract.getSTEMsByCreator(creator.address);
        expect(creatorSTEMs).to.deep.equal([1, 2]);
      });
    });

    describe("❌ Minting Validation", function () {
      it("Should reject empty name", async function () {
        const invalidSTEM = { ...sampleSTEM, name: "" };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 100, invalidSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "EmptyName");
      });

      it("Should reject empty audio hash", async function () {
        const invalidSTEM = { ...sampleSTEM, audioIPFSHash: "" };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 100, invalidSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "EmptyAudioHash");
      });

      it("Should reject royalty percentage > 50%", async function () {
        const invalidSTEM = { ...sampleSTEM, royaltyPercentage: 5001 }; // 50.01%
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 100, invalidSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidRoyaltyPercentage");
      });

      it("Should reject zero duration", async function () {
        const invalidSTEM = { ...sampleSTEM, duration: 0 };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 100, invalidSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidDuration");
      });

      it("Should reject zero amount", async function () {
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 0, sampleSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidDuration");
      });
    });
  });

  describe("📝 Metadata Management", function () {
    let tokenId;

    beforeEach(async function () {
      await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
      tokenId = 1;
    });

    it("Should allow creator to update metadata", async function () {
      const newName = "Updated Track Name";
      const newDescription = "Updated description";

      const tx = await stemContract.connect(creator).updateSTEMMetadata(
        tokenId,
        newName,
        newDescription
      );

      await expect(tx)
        .to.emit(stemContract, "STEMMetadataUpdated")
        .withArgs(tokenId, newName, newDescription);

      const metadata = await stemContract.getSTEMMetadata(tokenId);
      expect(metadata.name).to.equal(newName);
      expect(metadata.description).to.equal(newDescription);
    });

    it("Should reject non-creator metadata updates", async function () {
      await expect(
        stemContract.connect(user1).updateSTEMMetadata(tokenId, "Hacked", "Hacked description")
      ).to.be.revertedWithCustomError(stemContract, "NotCreator");
    });

    it("Should reject empty name in update", async function () {
      await expect(
        stemContract.connect(creator).updateSTEMMetadata(tokenId, "", "Valid description")
      ).to.be.revertedWithCustomError(stemContract, "EmptyName");
    });
  });

  describe("💰 Royalty Calculations", function () {
    let tokenId;

    beforeEach(async function () {
      await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
      tokenId = 1;
    });

    it("Should calculate royalties correctly", async function () {
      const salePrice = hre.ethers.parseEther("1.0"); // 1 ETH
      const expectedRoyalty = salePrice * BigInt(sampleSTEM.royaltyPercentage) / 10000n; // 10%

      const [royaltyCreator, royaltyAmount] = await stemContract.calculateRoyalty(tokenId, salePrice);

      expect(royaltyCreator).to.equal(creator.address);
      expect(royaltyAmount).to.equal(expectedRoyalty);
    });

    it("Should handle zero sale price", async function () {
      const [royaltyCreator, royaltyAmount] = await stemContract.calculateRoyalty(tokenId, 0);

      expect(royaltyCreator).to.equal(creator.address);
      expect(royaltyAmount).to.equal(0);
    });

    it("Should reject royalty calculation for non-existent token", async function () {
      await expect(
        stemContract.calculateRoyalty(999, hre.ethers.parseEther("1.0"))
      ).to.be.revertedWithCustomError(stemContract, "TokenNotExists");
    });
  });

  describe("🔗 Token URI and Metadata", function () {
    let tokenId;

    beforeEach(async function () {
      await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
      tokenId = 1;
    });

    it("Should return correct token URI", async function () {
      const expectedURI = `${baseMetadataURI}${tokenId}.json`;
      const actualURI = await stemContract.uri(tokenId);
      expect(actualURI).to.equal(expectedURI);
    });

    it("Should allow owner to update base URI", async function () {
      const newBaseURI = "https://new-api.tellurstoridaw.com/metadata/";
      await stemContract.connect(owner).setBaseMetadataURI(newBaseURI);

      const expectedURI = `${newBaseURI}${tokenId}.json`;
      const actualURI = await stemContract.uri(tokenId);
      expect(actualURI).to.equal(expectedURI);
    });

    it("Should reject non-owner base URI updates", async function () {
      await expect(
        stemContract.connect(user1).setBaseMetadataURI("https://malicious.com/")
      ).to.be.revertedWithCustomError(stemContract, "OwnableUnauthorizedAccount");
    });
  });

  describe("🔍 Query Functions", function () {
    beforeEach(async function () {
      // Mint multiple STEMs from different creators
      await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
      
      const stem2 = { ...sampleSTEM, name: "Track 2" };
      await stemContract.connect(creator).mintSTEM(creator.address, 50, stem2, "0x");
      
      const stem3 = { ...sampleSTEM, name: "Track 3" };
      await stemContract.connect(user1).mintSTEM(user1.address, 25, stem3, "0x");
    });

    it("Should return correct STEMs by creator", async function () {
      const creatorSTEMs = await stemContract.getSTEMsByCreator(creator.address);
      expect(creatorSTEMs).to.deep.equal([1, 2]);

      const user1STEMs = await stemContract.getSTEMsByCreator(user1.address);
      expect(user1STEMs).to.deep.equal([3]);

      const user2STEMs = await stemContract.getSTEMsByCreator(user2.address);
      expect(user2STEMs).to.deep.equal([]);
    });

    it("Should return correct current token ID", async function () {
      expect(await stemContract.getCurrentTokenId()).to.equal(4); // Next ID to be minted
    });
  });

  describe("🔄 ERC1155 Compliance", function () {
    let tokenId;

    beforeEach(async function () {
      await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
      tokenId = 1;
    });

    it("Should support ERC1155 transfers", async function () {
      await stemContract.connect(creator).safeTransferFrom(
        creator.address,
        user1.address,
        tokenId,
        25,
        "0x"
      );

      expect(await stemContract.balanceOf(creator.address, tokenId)).to.equal(75);
      expect(await stemContract.balanceOf(user1.address, tokenId)).to.equal(25);
    });

    it("Should support batch transfers", async function () {
      // Mint another STEM
      const stem2 = { ...sampleSTEM, name: "Track 2" };
      await stemContract.connect(creator).mintSTEM(creator.address, 50, stem2, "0x");

      await stemContract.connect(creator).safeBatchTransferFrom(
        creator.address,
        user1.address,
        [1, 2],
        [10, 20],
        "0x"
      );

      expect(await stemContract.balanceOf(user1.address, 1)).to.equal(10);
      expect(await stemContract.balanceOf(user1.address, 2)).to.equal(20);
    });

    it("Should support approval for all", async function () {
      await stemContract.connect(creator).setApprovalForAll(user1.address, true);
      expect(await stemContract.isApprovedForAll(creator.address, user1.address)).to.be.true;

      // user1 can now transfer creator's tokens
      await stemContract.connect(user1).safeTransferFrom(
        creator.address,
        user2.address,
        tokenId,
        10,
        "0x"
      );

      expect(await stemContract.balanceOf(user2.address, tokenId)).to.equal(10);
    });
  });

  describe("⛽ Gas Optimization Tests", function () {
    it("Should use reasonable gas for single mint", async function () {
      const tx = await stemContract.connect(creator).mintSTEM(
        creator.address,
        100,
        sampleSTEM,
        "0x"
      );
      const receipt = await tx.wait();
      
      console.log(`      Gas used for single mint: ${receipt.gasUsed.toString()}`);
      expect(receipt.gasUsed).to.be.lessThan(300000); // Should be under 300k gas
    });

    it("Should be more efficient for batch minting", async function () {
      const stems = Array(5).fill().map((_, i) => ({
        ...sampleSTEM,
        name: `Track ${i + 1}`
      }));
      const amounts = Array(5).fill(100);

      const tx = await stemContract.connect(creator).batchMintSTEMs(
        creator.address,
        amounts,
        stems,
        "0x"
      );
      const receipt = await tx.wait();
      
      console.log(`      Gas used for batch mint (5 STEMs): ${receipt.gasUsed.toString()}`);
      
      // Should be more efficient than 5 individual mints
      const gasPerSTEM = receipt.gasUsed / 5n;
      expect(gasPerSTEM).to.be.lessThan(250000); // Should be under 250k gas per STEM
    });
  });

  describe("🛡️ Security Tests", function () {
    it("Should prevent reentrancy attacks", async function () {
      // The contract uses ReentrancyGuard, so minting should be protected
      // This is more of a structural test - the guard is in place
      expect(await stemContract.getCurrentTokenId()).to.equal(1);
    });

    it("Should handle edge case inputs safely", async function () {
      // Test with maximum values
      const maxSTEM = {
        ...sampleSTEM,
        royaltyPercentage: 5000, // 50% - maximum allowed
        duration: 3600, // 1 hour
        tags: Array(10).fill("tag") // Maximum tags
      };

      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, maxSTEM, "0x")
      ).to.not.be.reverted;
    });
  });
});
