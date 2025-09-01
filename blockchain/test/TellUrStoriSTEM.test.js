import { expect } from "chai";
import { ethers } from "hardhat";

describe("TellUrStoriSTEM", function () {
  let stemContract;
  let owner, creator, buyer;
  let baseMetadataURI = "https://api.tellurstoridaw.com/metadata/";

  beforeEach(async function () {
    [owner, creator, buyer] = await ethers.getSigners();
    
    const TellUrStoriSTEM = await ethers.getContractFactory("TellUrStoriSTEM");
    stemContract = await TellUrStoriSTEM.deploy(baseMetadataURI);
    await stemContract.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await stemContract.owner()).to.equal(owner.address);
    });

    it("Should set the correct base metadata URI", async function () {
      // We can't directly check the private _baseMetadataURI, but we can test uri() function
      // First mint a token to test
      const metadata = {
        name: "Test STEM",
        description: "A test STEM token",
        audioIPFSHash: "QmTestAudioHash",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0, // Will be set by contract
        duration: 30,
        genre: "Electronic",
        tags: ["test", "electronic"],
        royaltyPercentage: 500 // 5%
      };

      await stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x");
      
      const tokenURI = await stemContract.uri(1);
      expect(tokenURI).to.equal(baseMetadataURI + "1.json");
    });
  });

  describe("STEM Minting", function () {
    it("Should mint a STEM token successfully", async function () {
      const metadata = {
        name: "Test STEM",
        description: "A test STEM token",
        audioIPFSHash: "QmTestAudioHash",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Electronic",
        tags: ["test", "electronic"],
        royaltyPercentage: 500
      };

      const tx = await stemContract.connect(creator).mintSTEM(creator.address, 10, metadata, "0x");
      const receipt = await tx.wait();

      // Check if STEMMinted event was emitted
      const event = receipt.logs.find(log => {
        try {
          const parsed = stemContract.interface.parseLog(log);
          return parsed.name === 'STEMMinted';
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;

      // Check token balance
      expect(await stemContract.balanceOf(creator.address, 1)).to.equal(10);

      // Check metadata
      const storedMetadata = await stemContract.getSTEMMetadata(1);
      expect(storedMetadata.name).to.equal("Test STEM");
      expect(storedMetadata.audioIPFSHash).to.equal("QmTestAudioHash");
      expect(storedMetadata.creator).to.equal(creator.address);
      expect(storedMetadata.royaltyPercentage).to.equal(500);
    });

    it("Should fail to mint with empty name", async function () {
      const metadata = {
        name: "",
        description: "A test STEM token",
        audioIPFSHash: "QmTestAudioHash",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Electronic",
        tags: ["test"],
        royaltyPercentage: 500
      };

      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
      ).to.be.revertedWithCustomError(stemContract, "EmptyName");
    });

    it("Should fail to mint with empty audio hash", async function () {
      const metadata = {
        name: "Test STEM",
        description: "A test STEM token",
        audioIPFSHash: "",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Electronic",
        tags: ["test"],
        royaltyPercentage: 500
      };

      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
      ).to.be.revertedWithCustomError(stemContract, "EmptyAudioHash");
    });

    it("Should fail to mint with invalid royalty percentage", async function () {
      const metadata = {
        name: "Test STEM",
        description: "A test STEM token",
        audioIPFSHash: "QmTestAudioHash",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Electronic",
        tags: ["test"],
        royaltyPercentage: 6000 // 60% - too high
      };

      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
      ).to.be.revertedWithCustomError(stemContract, "InvalidRoyaltyPercentage");
    });
  });

  describe("STEM Management", function () {
    beforeEach(async function () {
      const metadata = {
        name: "Test STEM",
        description: "A test STEM token",
        audioIPFSHash: "QmTestAudioHash",
        imageIPFSHash: "QmTestImageHash",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Electronic",
        tags: ["test", "electronic"],
        royaltyPercentage: 500
      };

      await stemContract.connect(creator).mintSTEM(creator.address, 10, metadata, "0x");
    });

    it("Should allow creator to update metadata", async function () {
      await stemContract.connect(creator).updateSTEMMetadata(1, "Updated STEM", "Updated description");
      
      const metadata = await stemContract.getSTEMMetadata(1);
      expect(metadata.name).to.equal("Updated STEM");
      expect(metadata.description).to.equal("Updated description");
    });

    it("Should not allow non-creator to update metadata", async function () {
      await expect(
        stemContract.connect(buyer).updateSTEMMetadata(1, "Hacked STEM", "Hacked description")
      ).to.be.revertedWithCustomError(stemContract, "NotCreator");
    });

    it("Should return creator's STEMs", async function () {
      const creatorSTEMs = await stemContract.getSTEMsByCreator(creator.address);
      expect(creatorSTEMs.length).to.equal(1);
      expect(creatorSTEMs[0]).to.equal(1);
    });

    it("Should calculate royalty correctly", async function () {
      const salePrice = ethers.parseEther("1"); // 1 ETH
      const [royaltyCreator, royaltyAmount] = await stemContract.calculateRoyalty(1, salePrice);
      
      expect(royaltyCreator).to.equal(creator.address);
      expect(royaltyAmount).to.equal(ethers.parseEther("0.05")); // 5% of 1 ETH
    });
  });

  describe("Batch Operations", function () {
    it("Should batch mint multiple STEMs", async function () {
      const metadata1 = {
        name: "STEM 1",
        description: "First STEM",
        audioIPFSHash: "QmHash1",
        imageIPFSHash: "QmImage1",
        creator: creator.address,
        createdAt: 0,
        duration: 30,
        genre: "Rock",
        tags: ["rock"],
        royaltyPercentage: 500
      };

      const metadata2 = {
        name: "STEM 2",
        description: "Second STEM",
        audioIPFSHash: "QmHash2",
        imageIPFSHash: "QmImage2",
        creator: creator.address,
        createdAt: 0,
        duration: 45,
        genre: "Jazz",
        tags: ["jazz"],
        royaltyPercentage: 750
      };

      const amounts = [5, 3];
      const metadataArray = [metadata1, metadata2];

      const tx = await stemContract.connect(creator).batchMintSTEMs(
        creator.address,
        amounts,
        metadataArray,
        "0x"
      );

      // Check balances
      expect(await stemContract.balanceOf(creator.address, 1)).to.equal(5);
      expect(await stemContract.balanceOf(creator.address, 2)).to.equal(3);

      // Check creator's STEMs
      const creatorSTEMs = await stemContract.getSTEMsByCreator(creator.address);
      expect(creatorSTEMs.length).to.equal(2);
    });
  });
});
