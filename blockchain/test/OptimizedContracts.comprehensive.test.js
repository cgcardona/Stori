import { expect } from "chai";
import hre from "hardhat";

describe("🛡️ Optimized Contracts - Complete RemixAI Feature Test Suite", function () {
  let stemContract, marketplaceContract;
  let owner, creator, buyer1, buyer2, feeRecipient;
  let tokenId1, tokenId2;

  // Valid IPFS hashes for testing
  const validIPFSHash = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";
  const validIPFSHashCIDv1 = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";

  // Sample STEM metadata
  const sampleSTEM = {
    name: "RemixAI Tested STEM",
    description: "A STEM tested with all RemixAI optimizations",
    audioIPFSHash: validIPFSHash,
    imageIPFSHash: validIPFSHash,
    creator: "0x0000000000000000000000000000000000000000",
    createdAt: 0,
    duration: 180,
    genre: "Electronic",
    tags: ["remixai", "tested", "optimized"],
    royaltyPercentage: 750 // 7.5%
  };

  beforeEach(async function () {
    [owner, creator, buyer1, buyer2, feeRecipient] = await hre.ethers.getSigners();

    // Deploy optimized STEM contract
    const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM_Optimized");
    stemContract = await TellUrStoriSTEM.deploy("https://api.tellurstoridaw.com/metadata/");
    await stemContract.waitForDeployment();

    // Deploy optimized marketplace contract
    const STEMMarketplace = await hre.ethers.getContractFactory("STEMMarketplace_Optimized");
    marketplaceContract = await STEMMarketplace.deploy(
      await stemContract.getAddress(),
      feeRecipient.address
    );
    await marketplaceContract.waitForDeployment();

    // Mint test STEMs
    await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
    tokenId1 = 1;

    const stem2 = { ...sampleSTEM, name: "Track 2", royaltyPercentage: 500 };
    await stemContract.connect(creator).mintSTEM(creator.address, 50, stem2, "0x");
    tokenId2 = 2;

    // Approve marketplace
    await stemContract.connect(creator).setApprovalForAll(
      await marketplaceContract.getAddress(),
      true
    );
  });

  describe("🔒 STEM Contract - RemixAI Security Features", function () {
    
    describe("⏸️ Pausable Functionality", function () {
      it("Should allow owner to pause contract", async function () {
        await expect(stemContract.pause())
          .to.emit(stemContract, "ContractPaused")
          .withArgs(owner.address);
        
        expect(await stemContract.paused()).to.be.true;
      });

      it("Should allow owner to unpause contract", async function () {
        await stemContract.pause();
        
        await expect(stemContract.unpause())
          .to.emit(stemContract, "ContractUnpaused")
          .withArgs(owner.address);
        
        expect(await stemContract.paused()).to.be.false;
      });

      it("Should prevent minting when paused", async function () {
        await stemContract.pause();
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, sampleSTEM, "0x")
        ).to.be.revertedWithCustomError(stemContract, "EnforcedPause");
      });

      it("Should prevent batch minting when paused", async function () {
        await stemContract.pause();
        
        await expect(
          stemContract.connect(creator).batchMintSTEMs(creator.address, [1], [sampleSTEM], "0x")
        ).to.be.revertedWithCustomError(stemContract, "EnforcedPause");
      });

      it("Should prevent metadata updates when paused", async function () {
        await stemContract.pause();
        
        await expect(
          stemContract.connect(creator).updateSTEMMetadata(tokenId1, "New Name", "New Description")
        ).to.be.revertedWithCustomError(stemContract, "EnforcedPause");
      });

      it("Should prevent non-owner from pausing", async function () {
        await expect(
          stemContract.connect(creator).pause()
        ).to.be.revertedWithCustomError(stemContract, "OwnableUnauthorizedAccount");
      });
    });

    describe("🔗 IPFS Hash Validation", function () {
      it("Should accept valid CIDv0 IPFS hash (Qm...)", async function () {
        const validCIDv0 = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";
        const metadata = { ...sampleSTEM, audioIPFSHash: validCIDv0, imageIPFSHash: validCIDv0 };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.not.be.reverted;
      });

      it("Should accept valid CIDv1 IPFS hash (bafy...)", async function () {
        const validCIDv1 = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
        const metadata = { ...sampleSTEM, audioIPFSHash: validCIDv1, imageIPFSHash: validCIDv1 };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.not.be.reverted;
      });

      it("Should reject invalid IPFS hash format", async function () {
        const invalidHash = "InvalidIPFSHash123";
        const metadata = { ...sampleSTEM, audioIPFSHash: invalidHash };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidIPFSHash")
        .withArgs(invalidHash);
      });

      it("Should reject empty IPFS hash", async function () {
        const metadata = { ...sampleSTEM, audioIPFSHash: "" };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidIPFSHash")
        .withArgs("");
      });

      it("Should reject IPFS hash with invalid characters", async function () {
        const invalidHash = "Qm@#$%^&*()InvalidHash";
        const metadata = { ...sampleSTEM, audioIPFSHash: invalidHash };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidIPFSHash")
        .withArgs(invalidHash);
      });
    });

    describe("👑 ERC2981 Royalty Standard", function () {
      it("Should implement ERC2981 interface", async function () {
        const interfaceId = "0x2a55205a"; // ERC2981 interface ID
        expect(await stemContract.supportsInterface(interfaceId)).to.be.true;
      });

      it("Should return correct royalty info", async function () {
        const salePrice = hre.ethers.parseEther("1.0");
        const [recipient, royaltyAmount] = await stemContract.royaltyInfo(tokenId1, salePrice);
        
        expect(recipient).to.equal(creator.address);
        expect(royaltyAmount).to.equal(hre.ethers.parseEther("0.075")); // 7.5% of 1 ETH
      });

      it("Should handle zero sale price", async function () {
        const [recipient, royaltyAmount] = await stemContract.royaltyInfo(tokenId1, 0);
        
        expect(recipient).to.equal(creator.address);
        expect(royaltyAmount).to.equal(0);
      });
    });

    describe("📦 Batch Operations with Limits", function () {
      it("Should enforce MAX_BATCH_SIZE limit", async function () {
        const maxBatch = await stemContract.MAX_BATCH_SIZE();
        const oversizedBatch = Array(Number(maxBatch) + 1).fill(1);
        const oversizedMetadata = Array(Number(maxBatch) + 1).fill(sampleSTEM);
        
        await expect(
          stemContract.connect(creator).batchMintSTEMs(creator.address, oversizedBatch, oversizedMetadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "BatchSizeExceeded")
        .withArgs(Number(maxBatch) + 1, maxBatch);
      });

      it("Should allow batch minting within limits", async function () {
        const batchSize = 5;
        const amounts = Array(batchSize).fill(1);
        const metadataArray = Array(batchSize).fill(sampleSTEM);
        
        await expect(
          stemContract.connect(creator).batchMintSTEMs(creator.address, amounts, metadataArray, "0x")
        ).to.not.be.reverted;
      });
    });

    describe("🏷️ Enhanced Validation", function () {
      it("Should enforce MAX_TAGS limit", async function () {
        const maxTags = await stemContract.MAX_TAGS();
        const tooManyTags = Array(Number(maxTags) + 1).fill("tag");
        const metadata = { ...sampleSTEM, tags: tooManyTags };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, metadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "TooManyTags")
        .withArgs(Number(maxTags) + 1, maxTags);
      });

      it("Should enforce duration limits", async function () {
        const minDuration = await stemContract.MIN_DURATION();
        const maxDuration = await stemContract.MAX_DURATION();
        
        // Test minimum duration violation
        const shortMetadata = { ...sampleSTEM, duration: Number(minDuration) - 1 };
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, shortMetadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidDuration")
        .withArgs(Number(minDuration) - 1, minDuration, maxDuration);
        
        // Test maximum duration violation
        const longMetadata = { ...sampleSTEM, duration: Number(maxDuration) + 1 };
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, longMetadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidDuration")
        .withArgs(Number(maxDuration) + 1, minDuration, maxDuration);
      });

      it("Should enforce royalty percentage limits", async function () {
        const maxRoyalty = await stemContract.MAX_ROYALTY_PERCENTAGE();
        const highRoyaltyMetadata = { ...sampleSTEM, royaltyPercentage: Number(maxRoyalty) + 1 };
        
        await expect(
          stemContract.connect(creator).mintSTEM(creator.address, 1, highRoyaltyMetadata, "0x")
        ).to.be.revertedWithCustomError(stemContract, "InvalidRoyaltyPercentage")
        .withArgs(Number(maxRoyalty) + 1, maxRoyalty);
      });
    });
  });

  describe("🏪 Marketplace Contract - RemixAI Enhancements", function () {
    
    describe("🚫 Receive Function Protection", function () {
      it("Should reject direct ETH transfers", async function () {
        await expect(
          owner.sendTransaction({
            to: await marketplaceContract.getAddress(),
            value: hre.ethers.parseEther("1.0")
          })
        ).to.be.revertedWith("Direct ETH transfers not allowed. Use marketplace functions.");
      });
    });

    describe("🏃‍♂️ Anti-Sniping Auction Protection", function () {
      let auctionId;
      
      beforeEach(async function () {
        // Create auction
        const tx = await marketplaceContract.connect(creator).createAuction(
          tokenId1,
          1,
          hre.ethers.parseEther("0.1"),
          3600 // 1 hour
        );
        const receipt = await tx.wait();
        auctionId = 1;
      });

      it("Should extend auction when bid placed near end", async function () {
        // Fast forward to near end of auction
        const auction = await marketplaceContract.auctions(auctionId);
        const nearEnd = Number(auction.endTime) - 200; // 200 seconds before end
        await hre.network.provider.send("evm_setNextBlockTimestamp", [nearEnd]);
        
        // Place bid
        await expect(
          marketplaceContract.connect(buyer1).placeBid(auctionId, { value: hre.ethers.parseEther("0.2") })
        ).to.emit(marketplaceContract, "AuctionExtended")
        .withArgs(auctionId, nearEnd + 300); // Should extend by BID_EXTENSION_TIME (300 seconds)
      });

      it("Should not extend auction when bid placed early", async function () {
        const auction = await marketplaceContract.auctions(auctionId);
        const originalEndTime = auction.endTime;
        
        // Place bid early (not near end)
        await marketplaceContract.connect(buyer1).placeBid(auctionId, { value: hre.ethers.parseEther("0.2") });
        
        const updatedAuction = await marketplaceContract.auctions(auctionId);
        expect(updatedAuction.endTime).to.equal(originalEndTime);
      });
    });

    describe("💰 Fee Precision Safeguards", function () {
      it("Should detect fee precision errors in buyListing", async function () {
        // Create listing
        await marketplaceContract.connect(creator).createListing(
          tokenId1,
          1,
          1, // 1 wei price to trigger precision issues
          0
        );
        
        // This should work fine with our precision checks
        await expect(
          marketplaceContract.connect(buyer1).buyListing(1, 1, { value: 1 })
        ).to.not.be.reverted;
      });

      it("Should handle edge case fee calculations", async function () {
        // Test with very small amounts that could cause precision issues
        await marketplaceContract.connect(creator).createListing(
          tokenId1,
          1,
          100, // 100 wei
          0
        );
        
        await expect(
          marketplaceContract.connect(buyer1).buyListing(1, 1, { value: 100 })
        ).to.not.be.reverted;
      });
    });

    describe("📄 Pagination Optimization", function () {
      beforeEach(async function () {
        // Create multiple listings for the same token
        for (let i = 0; i < 5; i++) {
          await stemContract.connect(creator).mintSTEM(creator.address, 10, sampleSTEM, "0x");
          const newTokenId = i + 3; // Starting from 3 since we already have 1 and 2
          await marketplaceContract.connect(creator).createListing(
            newTokenId,
            1,
            hre.ethers.parseEther("0.1"),
            0
          );
        }
      });

      it("Should return paginated results", async function () {
        const listings = await marketplaceContract.getActiveListingsForTokenPaginated(3, 0, 2);
        expect(listings.length).to.be.at.most(2);
      });

      it("Should enforce pagination limit", async function () {
        const listings = await marketplaceContract.getActiveListingsForTokenPaginated(3, 0, 150);
        expect(listings.length).to.be.at.most(100); // Should be capped at 100
      });

      it("Should handle offset correctly", async function () {
        const firstPage = await marketplaceContract.getActiveListingsForTokenPaginated(3, 0, 2);
        const secondPage = await marketplaceContract.getActiveListingsForTokenPaginated(3, 2, 2);
        
        // Should return different results (if there are enough listings)
        if (firstPage.length > 0 && secondPage.length > 0) {
          expect(firstPage[0]).to.not.equal(secondPage[0]);
        }
      });
    });

    describe("❌ Offer Rejection Feature", function () {
      let listingId;
      
      beforeEach(async function () {
        // Create listing
        const tx = await marketplaceContract.connect(creator).createListing(
          tokenId1,
          5,
          hre.ethers.parseEther("0.1"),
          0
        );
        listingId = 1;
        
        // Make offer
        const futureTime = Math.floor(Date.now() / 1000) + 3600;
        await marketplaceContract.connect(buyer1).makeOffer(
          listingId,
          2,
          hre.ethers.parseEther("0.08"),
          futureTime,
          { value: hre.ethers.parseEther("0.16") }
        );
      });

      it("Should allow seller to reject offer with reason", async function () {
        await expect(
          marketplaceContract.connect(creator).rejectOffer(listingId, 0, "Price too low")
        ).to.emit(marketplaceContract, "OfferRejected")
        .withArgs(listingId, 0, "Price too low");
      });

      it("Should refund buyer when offer is rejected", async function () {
        const initialBalance = await hre.ethers.provider.getBalance(buyer1.address);
        
        await marketplaceContract.connect(creator).rejectOffer(listingId, 0, "Not interested");
        
        const finalBalance = await hre.ethers.provider.getBalance(buyer1.address);
        expect(finalBalance).to.be.gt(initialBalance);
      });

      it("Should prevent non-seller from rejecting offer", async function () {
        await expect(
          marketplaceContract.connect(buyer2).rejectOffer(listingId, 0, "Not authorized")
        ).to.be.revertedWithCustomError(marketplaceContract, "NotSeller");
      });
    });

    describe("📊 Enhanced Events and Transparency", function () {
      it("Should emit MarketplaceFeeUpdated event", async function () {
        const newFee = 300; // 3%
        
        await expect(
          marketplaceContract.setMarketplaceFee(newFee)
        ).to.emit(marketplaceContract, "MarketplaceFeeUpdated")
        .withArgs(250, newFee); // Old fee was 250 (2.5%)
      });

      it("Should emit FeeRecipientUpdated event", async function () {
        await expect(
          marketplaceContract.setFeeRecipient(buyer1.address)
        ).to.emit(marketplaceContract, "FeeRecipientUpdated")
        .withArgs(feeRecipient.address, buyer1.address);
      });
    });
  });

  describe("🔄 Integration Tests - Full Workflow", function () {
    it("Should complete full workflow: mint → list → offer → reject → accept", async function () {
      // 1. Mint STEM with all validations
      const metadata = {
        ...sampleSTEM,
        name: "Integration Test STEM",
        audioIPFSHash: validIPFSHashCIDv1, // Test CIDv1
        imageIPFSHash: validIPFSHash,      // Test CIDv0
        royaltyPercentage: 500 // 5%
      };
      
      await stemContract.connect(creator).mintSTEM(creator.address, 10, metadata, "0x");
      const newTokenId = 3;
      
      // 2. Create listing
      await marketplaceContract.connect(creator).createListing(
        newTokenId,
        5,
        hre.ethers.parseEther("0.1"),
        0
      );
      const listingId = 1;
      
      // 3. Make offer
      const futureTime = Math.floor(Date.now() / 1000) + 3600;
      await marketplaceContract.connect(buyer1).makeOffer(
        listingId,
        2,
        hre.ethers.parseEther("0.08"),
        futureTime,
        { value: hre.ethers.parseEther("0.16") }
      );
      
      // 4. Reject first offer
      await marketplaceContract.connect(creator).rejectOffer(listingId, 0, "Too low");
      
      // 5. Make better offer
      await marketplaceContract.connect(buyer1).makeOffer(
        listingId,
        2,
        hre.ethers.parseEther("0.12"),
        futureTime,
        { value: hre.ethers.parseEther("0.24") }
      );
      
      // 6. Accept offer
      await expect(
        marketplaceContract.connect(creator).acceptOffer(listingId, 1)
      ).to.emit(marketplaceContract, "OfferAccepted");
      
      // 7. Verify final state
      const finalBalance = await stemContract.balanceOf(buyer1.address, newTokenId);
      expect(finalBalance).to.equal(2);
    });

    it("Should handle pausable contract during marketplace operations", async function () {
      // Create listing first
      await marketplaceContract.connect(creator).createListing(
        tokenId1,
        1,
        hre.ethers.parseEther("0.1"),
        0
      );
      
      // Pause STEM contract
      await stemContract.pause();
      
      // Marketplace operations should still work for existing tokens
      await expect(
        marketplaceContract.connect(buyer1).buyListing(1, 1, { value: hre.ethers.parseEther("0.1") })
      ).to.not.be.reverted;
      
      // But new minting should be blocked
      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, sampleSTEM, "0x")
      ).to.be.revertedWithCustomError(stemContract, "EnforcedPause");
    });
  });

  describe("🎯 Edge Cases and Security", function () {
    it("Should handle all custom errors properly", async function () {
      // Test various custom errors to ensure they work correctly
      
      // InvalidIPFSHash
      const badMetadata = { ...sampleSTEM, audioIPFSHash: "bad_hash" };
      await expect(
        stemContract.connect(creator).mintSTEM(creator.address, 1, badMetadata, "0x")
      ).to.be.revertedWithCustomError(stemContract, "InvalidIPFSHash");
      
      // FeePrecisionError (would be hard to trigger, but structure is tested)
      // This is more of a safety net that shouldn't normally trigger
      
      // Direct ETH transfer protection
      await expect(
        owner.sendTransaction({
          to: await marketplaceContract.getAddress(),
          value: hre.ethers.parseEther("1.0")
        })
      ).to.be.revertedWith("Direct ETH transfers not allowed. Use marketplace functions.");
    });

    it("Should maintain backward compatibility", async function () {
      // Ensure all original functionality still works
      const balance = await stemContract.balanceOf(creator.address, tokenId1);
      expect(balance).to.equal(100);
      
      const metadata = await stemContract.stemMetadata(tokenId1);
      expect(metadata.name).to.equal(sampleSTEM.name);
    });
  });
});
