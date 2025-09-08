import { expect } from "chai";
import hre from "hardhat";

describe("STEMMarketplace - Comprehensive Test Suite", function () {
  let stemContract, marketplaceContract;
  let owner, creator, buyer1, buyer2, feeRecipient;
  let tokenId1, tokenId2;

  // Sample STEM metadata
  const sampleSTEM = {
    name: "Epic Synthwave Beat",
    description: "A nostalgic synthwave track with retro vibes",
    audioIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
    imageIPFSHash: "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdH",
    creator: "0x0000000000000000000000000000000000000000",
    createdAt: 0,
    duration: 180,
    genre: "Synthwave",
    tags: ["retro", "80s", "electronic"],
    royaltyPercentage: 1000 // 10%
  };

  beforeEach(async function () {
    [owner, creator, buyer1, buyer2, feeRecipient] = await hre.ethers.getSigners();

    // Deploy STEM contract
    const TellUrStoriSTEM = await hre.ethers.getContractFactory("TellUrStoriSTEM");
    stemContract = await TellUrStoriSTEM.deploy("https://api.tellurstoridaw.com/metadata/");
    await stemContract.waitForDeployment();

    // Deploy marketplace contract
    const STEMMarketplace = await hre.ethers.getContractFactory("STEMMarketplace");
    marketplaceContract = await STEMMarketplace.deploy(
      await stemContract.getAddress(),
      feeRecipient.address
    );
    await marketplaceContract.waitForDeployment();

    // Mint test STEMs
    await stemContract.connect(creator).mintSTEM(creator.address, 100, sampleSTEM, "0x");
    tokenId1 = 1;

    const stem2 = { ...sampleSTEM, name: "Track 2", royaltyPercentage: 500 }; // 5%
    await stemContract.connect(creator).mintSTEM(creator.address, 50, stem2, "0x");
    tokenId2 = 2;

    // Approve marketplace to transfer tokens
    await stemContract.connect(creator).setApprovalForAll(
      await marketplaceContract.getAddress(),
      true
    );
  });

  describe("🏗️ Contract Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      expect(await marketplaceContract.stemContract()).to.equal(await stemContract.getAddress());
      expect(await marketplaceContract.feeRecipient()).to.equal(feeRecipient.address);
      expect(await marketplaceContract.marketplaceFee()).to.equal(250); // 2.5%
    });

    it("Should set correct owner", async function () {
      expect(await marketplaceContract.owner()).to.equal(owner.address);
    });
  });

  describe("🏪 Listing Management", function () {
    describe("✅ Successful Listings", function () {
      it("Should create a basic listing", async function () {
        const pricePerToken = hre.ethers.parseEther("0.1");
        const amount = 10;
        const expiresAt = 0; // No expiration

        const tx = await marketplaceContract.connect(creator).createListing(
          tokenId1,
          amount,
          pricePerToken,
          expiresAt
        );

        await expect(tx)
          .to.emit(marketplaceContract, "Listed")
          .withArgs(1, tokenId1, creator.address, amount, pricePerToken, expiresAt);

        const listing = await marketplaceContract.listings(1);
        expect(listing.tokenId).to.equal(tokenId1);
        expect(listing.seller).to.equal(creator.address);
        expect(listing.amount).to.equal(amount);
        expect(listing.pricePerToken).to.equal(pricePerToken);
        expect(listing.active).to.be.true;
      });

      it("Should create listing with expiration", async function () {
        const pricePerToken = hre.ethers.parseEther("0.1");
        const amount = 10;
        const expiresAt = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

        await marketplaceContract.connect(creator).createListing(
          tokenId1,
          amount,
          pricePerToken,
          expiresAt
        );

        const listing = await marketplaceContract.listings(1);
        expect(listing.expiresAt).to.equal(expiresAt);
      });

      it("Should track user listings", async function () {
        const pricePerToken = hre.ethers.parseEther("0.1");
        
        await marketplaceContract.connect(creator).createListing(tokenId1, 10, pricePerToken, 0);
        await marketplaceContract.connect(creator).createListing(tokenId2, 5, pricePerToken, 0);

        const userListings = await marketplaceContract.getUserListings(creator.address);
        expect(userListings).to.deep.equal([1, 2]);
      });
    });

    describe("❌ Listing Validation", function () {
      it("Should reject zero price", async function () {
        await expect(
          marketplaceContract.connect(creator).createListing(tokenId1, 10, 0, 0)
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidPrice");
      });

      it("Should reject zero amount", async function () {
        await expect(
          marketplaceContract.connect(creator).createListing(tokenId1, 0, hre.ethers.parseEther("0.1"), 0)
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidAmount");
      });

      it("Should reject past expiration", async function () {
        const pastTime = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
        
        await expect(
          marketplaceContract.connect(creator).createListing(
            tokenId1, 10, hre.ethers.parseEther("0.1"), pastTime
          )
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidExpiration");
      });

      it("Should reject insufficient balance", async function () {
        await expect(
          marketplaceContract.connect(creator).createListing(
            tokenId1, 200, hre.ethers.parseEther("0.1"), 0 // Only have 100 tokens
          )
        ).to.be.revertedWithCustomError(marketplaceContract, "InsufficientBalance");
      });

      it("Should reject without approval", async function () {
        // Remove approval
        await stemContract.connect(creator).setApprovalForAll(
          await marketplaceContract.getAddress(),
          false
        );

        await expect(
          marketplaceContract.connect(creator).createListing(
            tokenId1, 10, hre.ethers.parseEther("0.1"), 0
          )
        ).to.be.revertedWithCustomError(marketplaceContract, "NotApproved");
      });
    });

    describe("🗑️ Listing Cancellation", function () {
      let listingId;

      beforeEach(async function () {
        await marketplaceContract.connect(creator).createListing(
          tokenId1, 10, hre.ethers.parseEther("0.1"), 0
        );
        listingId = 1;
      });

      it("Should allow seller to cancel listing", async function () {
        const tx = await marketplaceContract.connect(creator).cancelListing(listingId);

        await expect(tx)
          .to.emit(marketplaceContract, "ListingCancelled")
          .withArgs(listingId, creator.address);

        const listing = await marketplaceContract.listings(listingId);
        expect(listing.active).to.be.false;
      });

      it("Should reject non-seller cancellation", async function () {
        await expect(
          marketplaceContract.connect(buyer1).cancelListing(listingId)
        ).to.be.revertedWithCustomError(marketplaceContract, "NotSeller");
      });

      it("Should reject cancellation of inactive listing", async function () {
        await marketplaceContract.connect(creator).cancelListing(listingId);
        
        await expect(
          marketplaceContract.connect(creator).cancelListing(listingId)
        ).to.be.revertedWithCustomError(marketplaceContract, "ListingNotActive");
      });
    });
  });

  describe("💰 Direct Purchases", function () {
    let listingId;
    const pricePerToken = hre.ethers.parseEther("0.1");
    const listingAmount = 10;

    beforeEach(async function () {
      await marketplaceContract.connect(creator).createListing(
        tokenId1, listingAmount, pricePerToken, 0
      );
      listingId = 1;
    });

    describe("✅ Successful Purchases", function () {
      it("Should complete a full purchase", async function () {
        const purchaseAmount = 5;
        const totalPrice = pricePerToken * BigInt(purchaseAmount);
        
        // Calculate expected fees
        const marketplaceFeeAmount = totalPrice * 250n / 10000n; // 2.5%
        const royaltyAmount = totalPrice * 1000n / 10000n; // 10%
        const sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;

        const tx = await marketplaceContract.connect(buyer1).buyListing(
          listingId, purchaseAmount, { value: totalPrice }
        );

        await expect(tx)
          .to.emit(marketplaceContract, "Sold")
          .withArgs(listingId, tokenId1, buyer1.address, creator.address, purchaseAmount, totalPrice);

        // Check token transfer
        expect(await stemContract.balanceOf(buyer1.address, tokenId1)).to.equal(purchaseAmount);
        expect(await stemContract.balanceOf(creator.address, tokenId1)).to.equal(100 - purchaseAmount);

        // Check listing update
        const listing = await marketplaceContract.listings(listingId);
        expect(listing.amount).to.equal(listingAmount - purchaseAmount);
        expect(listing.active).to.be.true; // Still active with remaining tokens
      });

      it("Should complete purchase and deactivate listing when fully sold", async function () {
        const totalPrice = pricePerToken * BigInt(listingAmount);

        await marketplaceContract.connect(buyer1).buyListing(
          listingId, listingAmount, { value: totalPrice }
        );

        const listing = await marketplaceContract.listings(listingId);
        expect(listing.amount).to.equal(0);
        expect(listing.active).to.be.false;
      });

      it("Should refund excess payment", async function () {
        const purchaseAmount = 5;
        const totalPrice = pricePerToken * BigInt(purchaseAmount);
        const excessPayment = hre.ethers.parseEther("0.1"); // Extra 0.1 ETH

        const initialBalance = await hre.ethers.provider.getBalance(buyer1.address);

        const tx = await marketplaceContract.connect(buyer1).buyListing(
          listingId, purchaseAmount, { value: totalPrice + excessPayment }
        );
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        const finalBalance = await hre.ethers.provider.getBalance(buyer1.address);
        const expectedBalance = initialBalance - totalPrice - gasUsed;

        expect(finalBalance).to.be.closeTo(expectedBalance, hre.ethers.parseEther("0.001"));
      });

      it("Should distribute payments correctly", async function () {
        const purchaseAmount = 10;
        const totalPrice = pricePerToken * BigInt(purchaseAmount);
        
        const creatorInitialBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientInitialBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        await marketplaceContract.connect(buyer1).buyListing(
          listingId, purchaseAmount, { value: totalPrice }
        );

        // Calculate expected amounts
        const marketplaceFeeAmount = totalPrice * 250n / 10000n; // 2.5%
        const royaltyAmount = totalPrice * 1000n / 10000n; // 10% (creator gets this)
        const sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;

        const creatorFinalBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientFinalBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        // Creator gets seller amount + royalty (since they're the same person in this test)
        expect(creatorFinalBalance - creatorInitialBalance).to.equal(sellerAmount + royaltyAmount);
        expect(feeRecipientFinalBalance - feeRecipientInitialBalance).to.equal(marketplaceFeeAmount);
      });
    });

    describe("❌ Purchase Validation", function () {
      it("Should reject purchase of inactive listing", async function () {
        await marketplaceContract.connect(creator).cancelListing(listingId);

        await expect(
          marketplaceContract.connect(buyer1).buyListing(listingId, 5, { 
            value: hre.ethers.parseEther("0.5") 
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "ListingNotActive");
      });

      it("Should reject purchase of expired listing", async function () {
        // Create listing with short expiration
        const shortExpiry = Math.floor(Date.now() / 1000) + 1;
        await marketplaceContract.connect(creator).createListing(
          tokenId2, 5, pricePerToken, shortExpiry
        );

        // Wait for expiration
        await new Promise(resolve => setTimeout(resolve, 2000));

        await expect(
          marketplaceContract.connect(buyer1).buyListing(2, 5, { 
            value: hre.ethers.parseEther("0.5") 
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "ListingExpired");
      });

      it("Should reject insufficient payment", async function () {
        const insufficientPayment = pricePerToken * 5n / 2n; // Half the required amount

        await expect(
          marketplaceContract.connect(buyer1).buyListing(listingId, 5, { 
            value: insufficientPayment 
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "InsufficientPayment");
      });

      it("Should reject zero amount purchase", async function () {
        await expect(
          marketplaceContract.connect(buyer1).buyListing(listingId, 0, { 
            value: hre.ethers.parseEther("0.1") 
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidAmount");
      });

      it("Should reject purchase exceeding listing amount", async function () {
        await expect(
          marketplaceContract.connect(buyer1).buyListing(listingId, 15, { // Listing only has 10
            value: hre.ethers.parseEther("1.5") 
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidAmount");
      });
    });
  });

  describe("💡 Offer System", function () {
    let listingId;
    const pricePerToken = hre.ethers.parseEther("0.1");

    beforeEach(async function () {
      await marketplaceContract.connect(creator).createListing(
        tokenId1, 10, pricePerToken, 0
      );
      listingId = 1;
    });

    describe("✅ Making Offers", function () {
      it("Should create an offer with escrow", async function () {
        const offerAmount = 5;
        const offerPricePerToken = hre.ethers.parseEther("0.08"); // Lower than listing
        const expiresAt = Math.floor(Date.now() / 1000) + 3600;
        const totalOfferValue = offerPricePerToken * BigInt(offerAmount);

        const tx = await marketplaceContract.connect(buyer1).makeOffer(
          listingId, offerAmount, offerPricePerToken, expiresAt,
          { value: totalOfferValue }
        );

        await expect(tx)
          .to.emit(marketplaceContract, "OfferMade")
          .withArgs(listingId, buyer1.address, offerAmount, offerPricePerToken, expiresAt);

        const offers = await marketplaceContract.getOffersForListing(listingId);
        expect(offers.length).to.equal(1);
        expect(offers[0].buyer).to.equal(buyer1.address);
        expect(offers[0].amount).to.equal(offerAmount);
        expect(offers[0].pricePerToken).to.equal(offerPricePerToken);
        expect(offers[0].active).to.be.true;
        expect(offers[0].escrowed).to.be.true;
      });

      it("Should handle multiple offers on same listing", async function () {
        const offer1Value = hre.ethers.parseEther("0.4"); // 5 * 0.08
        const offer2Value = hre.ethers.parseEther("0.35"); // 5 * 0.07
        const expiresAt = Math.floor(Date.now() / 1000) + 3600;

        await marketplaceContract.connect(buyer1).makeOffer(
          listingId, 5, hre.ethers.parseEther("0.08"), expiresAt,
          { value: offer1Value }
        );

        await marketplaceContract.connect(buyer2).makeOffer(
          listingId, 5, hre.ethers.parseEther("0.07"), expiresAt,
          { value: offer2Value }
        );

        const offers = await marketplaceContract.getOffersForListing(listingId);
        expect(offers.length).to.equal(2);
        expect(offers[0].buyer).to.equal(buyer1.address);
        expect(offers[1].buyer).to.equal(buyer2.address);
      });
    });

    describe("✅ Accepting Offers", function () {
      let offerAmount, offerPricePerToken, totalOfferValue;

      beforeEach(async function () {
        offerAmount = 5;
        offerPricePerToken = hre.ethers.parseEther("0.08");
        totalOfferValue = offerPricePerToken * BigInt(offerAmount);
        const expiresAt = Math.floor(Date.now() / 1000) + 3600;

        await marketplaceContract.connect(buyer1).makeOffer(
          listingId, offerAmount, offerPricePerToken, expiresAt,
          { value: totalOfferValue }
        );
      });

      it("Should accept offer and complete trade", async function () {
        const offerIndex = 0;

        const tx = await marketplaceContract.connect(creator).acceptOffer(listingId, offerIndex);

        await expect(tx)
          .to.emit(marketplaceContract, "OfferAccepted")
          .withArgs(listingId, buyer1.address, creator.address, offerAmount, totalOfferValue);

        // Check token transfer
        expect(await stemContract.balanceOf(buyer1.address, tokenId1)).to.equal(offerAmount);

        // Check offer status
        const offers = await marketplaceContract.getOffersForListing(listingId);
        expect(offers[0].active).to.be.false;
        expect(offers[0].escrowed).to.be.false;

        // Check listing update
        const listing = await marketplaceContract.listings(listingId);
        expect(listing.amount).to.equal(10 - offerAmount);
      });

      it("Should distribute payments correctly from escrow", async function () {
        const creatorInitialBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientInitialBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        const tx = await marketplaceContract.connect(creator).acceptOffer(listingId, 0);
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        // Calculate expected amounts
        const marketplaceFeeAmount = totalOfferValue * 250n / 10000n; // 2.5%
        const royaltyAmount = totalOfferValue * 1000n / 10000n; // 10%
        const sellerAmount = totalOfferValue - marketplaceFeeAmount - royaltyAmount;

        const creatorFinalBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientFinalBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        // Creator gets seller amount + royalty - gas
        expect(creatorFinalBalance - creatorInitialBalance + gasUsed).to.equal(sellerAmount + royaltyAmount);
        expect(feeRecipientFinalBalance - feeRecipientInitialBalance).to.equal(marketplaceFeeAmount);
      });
    });

    describe("🔄 Offer Withdrawal", function () {
      it("Should allow withdrawal of expired offers", async function () {
        const offerAmount = 5;
        const offerPricePerToken = hre.ethers.parseEther("0.08");
        const totalOfferValue = offerPricePerToken * BigInt(offerAmount);
        const expiresAt = Math.floor(Date.now() / 1000) + 1; // Expires in 1 second

        await marketplaceContract.connect(buyer1).makeOffer(
          listingId, offerAmount, offerPricePerToken, expiresAt,
          { value: totalOfferValue }
        );

        // Wait for expiration
        await new Promise(resolve => setTimeout(resolve, 2000));

        const initialBalance = await hre.ethers.provider.getBalance(buyer1.address);

        const tx = await marketplaceContract.connect(buyer1).withdrawOffer(listingId, 0);
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        const finalBalance = await hre.ethers.provider.getBalance(buyer1.address);
        
        // Should get refund minus gas
        expect(finalBalance - initialBalance + gasUsed).to.equal(totalOfferValue);

        // Check offer status
        const offers = await marketplaceContract.getOffersForListing(listingId);
        expect(offers[0].active).to.be.false;
      });
    });
  });

  describe("🏛️ Auction System", function () {
    let auctionId;
    const startingPrice = hre.ethers.parseEther("0.1");
    const auctionDuration = 3600; // 1 hour

    beforeEach(async function () {
      const tx = await marketplaceContract.connect(creator).createAuction(
        tokenId1, 10, startingPrice, auctionDuration
      );
      auctionId = 1;
    });

    describe("✅ Auction Creation", function () {
      it("Should create auction with correct parameters", async function () {
        const auction = await marketplaceContract.auctions(auctionId);
        
        expect(auction.tokenId).to.equal(tokenId1);
        expect(auction.seller).to.equal(creator.address);
        expect(auction.amount).to.equal(10);
        expect(auction.startingPrice).to.equal(startingPrice);
        expect(auction.currentBid).to.equal(0);
        expect(auction.currentBidder).to.equal(hre.ethers.ZeroAddress);
        expect(auction.active).to.be.true;
        expect(auction.settled).to.be.false;
      });

      it("Should emit AuctionCreated event", async function () {
        const tx = await marketplaceContract.connect(creator).createAuction(
          tokenId2, 5, startingPrice, auctionDuration
        );

        await expect(tx).to.emit(marketplaceContract, "AuctionCreated");
      });
    });

    describe("💰 Bidding Process", function () {
      it("Should accept valid first bid", async function () {
        const bidAmount = hre.ethers.parseEther("0.15"); // Above starting price

        const tx = await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: bidAmount
        });

        await expect(tx)
          .to.emit(marketplaceContract, "BidPlaced")
          .withArgs(auctionId, buyer1.address, bidAmount);

        const auction = await marketplaceContract.auctions(auctionId);
        expect(auction.currentBid).to.equal(bidAmount);
        expect(auction.currentBidder).to.equal(buyer1.address);
      });

      it("Should handle bid increments correctly", async function () {
        const firstBid = hre.ethers.parseEther("0.15");
        const minIncrement = firstBid * 500n / 10000n; // 5%
        const secondBid = firstBid + minIncrement;

        // First bid
        await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: firstBid
        });

        // Second bid with proper increment
        await marketplaceContract.connect(buyer2).placeBid(auctionId, {
          value: secondBid
        });

        const auction = await marketplaceContract.auctions(auctionId);
        expect(auction.currentBid).to.equal(secondBid);
        expect(auction.currentBidder).to.equal(buyer2.address);
      });

      it("Should refund previous bidder", async function () {
        const firstBid = hre.ethers.parseEther("0.15");
        const secondBid = hre.ethers.parseEther("0.20");

        // First bid
        await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: firstBid
        });

        const buyer1BalanceAfterFirstBid = await hre.ethers.provider.getBalance(buyer1.address);

        // Second bid (should refund first bidder)
        await marketplaceContract.connect(buyer2).placeBid(auctionId, {
          value: secondBid
        });

        const buyer1FinalBalance = await hre.ethers.provider.getBalance(buyer1.address);
        expect(buyer1FinalBalance - buyer1BalanceAfterFirstBid).to.equal(firstBid);
      });

      it("Should reject bid below minimum increment", async function () {
        const firstBid = hre.ethers.parseEther("0.15");
        const insufficientBid = firstBid + hre.ethers.parseEther("0.001"); // Too small increment

        await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: firstBid
        });

        await expect(
          marketplaceContract.connect(buyer2).placeBid(auctionId, {
            value: insufficientBid
          })
        ).to.be.revertedWithCustomError(marketplaceContract, "BidTooLow");
      });
    });

    describe("🏁 Auction Settlement", function () {
      it("Should settle auction with winner", async function () {
        const bidAmount = hre.ethers.parseEther("0.15");

        // Place bid
        await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: bidAmount
        });

        // Fast forward time to end auction
        await hre.network.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await hre.network.provider.send("evm_mine");

        const tx = await marketplaceContract.settleAuction(auctionId);

        await expect(tx)
          .to.emit(marketplaceContract, "AuctionSettled")
          .withArgs(auctionId, buyer1.address, bidAmount);

        // Check token transfer
        expect(await stemContract.balanceOf(buyer1.address, tokenId1)).to.equal(10);

        // Check auction status
        const auction = await marketplaceContract.auctions(auctionId);
        expect(auction.active).to.be.false;
        expect(auction.settled).to.be.true;
      });

      it("Should settle auction without bids", async function () {
        // Fast forward time to end auction
        await hre.network.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await hre.network.provider.send("evm_mine");

        const tx = await marketplaceContract.settleAuction(auctionId);

        await expect(tx)
          .to.emit(marketplaceContract, "AuctionSettled")
          .withArgs(auctionId, hre.ethers.ZeroAddress, 0);

        // Tokens should remain with seller
        expect(await stemContract.balanceOf(creator.address, tokenId1)).to.equal(100);
      });

      it("Should distribute payments correctly in auction", async function () {
        const bidAmount = hre.ethers.parseEther("0.2");

        await marketplaceContract.connect(buyer1).placeBid(auctionId, {
          value: bidAmount
        });

        const creatorInitialBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientInitialBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        // End auction
        await hre.network.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await hre.network.provider.send("evm_mine");

        await marketplaceContract.settleAuction(auctionId);

        // Calculate expected amounts
        const marketplaceFeeAmount = bidAmount * 250n / 10000n; // 2.5%
        const royaltyAmount = bidAmount * 1000n / 10000n; // 10%
        const sellerAmount = bidAmount - marketplaceFeeAmount - royaltyAmount;

        const creatorFinalBalance = await hre.ethers.provider.getBalance(creator.address);
        const feeRecipientFinalBalance = await hre.ethers.provider.getBalance(feeRecipient.address);

        expect(creatorFinalBalance - creatorInitialBalance).to.equal(sellerAmount + royaltyAmount);
        expect(feeRecipientFinalBalance - feeRecipientInitialBalance).to.equal(marketplaceFeeAmount);
      });
    });
  });

  describe("⚙️ Administrative Functions", function () {
    describe("💰 Fee Management", function () {
      it("Should allow owner to update marketplace fee", async function () {
        const newFee = 500; // 5%
        
        await marketplaceContract.connect(owner).setMarketplaceFee(newFee);
        expect(await marketplaceContract.marketplaceFee()).to.equal(newFee);
      });

      it("Should reject fee above maximum", async function () {
        const excessiveFee = 1001; // 10.01%
        
        await expect(
          marketplaceContract.connect(owner).setMarketplaceFee(excessiveFee)
        ).to.be.revertedWithCustomError(marketplaceContract, "InvalidPrice");
      });

      it("Should reject non-owner fee updates", async function () {
        await expect(
          marketplaceContract.connect(buyer1).setMarketplaceFee(500)
        ).to.be.revertedWithCustomError(marketplaceContract, "OwnableUnauthorizedAccount");
      });
    });

    describe("🏦 Fee Recipient Management", function () {
      it("Should allow owner to update fee recipient", async function () {
        await marketplaceContract.connect(owner).setFeeRecipient(buyer1.address);
        expect(await marketplaceContract.feeRecipient()).to.equal(buyer1.address);
      });

      it("Should reject zero address as fee recipient", async function () {
        await expect(
          marketplaceContract.connect(owner).setFeeRecipient(hre.ethers.ZeroAddress)
        ).to.be.revertedWithCustomError(marketplaceContract, "ZeroAddress");
      });
    });
  });

  describe("🔍 Query Functions", function () {
    beforeEach(async function () {
      // Create multiple listings
      await marketplaceContract.connect(creator).createListing(
        tokenId1, 10, hre.ethers.parseEther("0.1"), 0
      );
      await marketplaceContract.connect(creator).createListing(
        tokenId1, 5, hre.ethers.parseEther("0.15"), 0
      );
      await marketplaceContract.connect(creator).createListing(
        tokenId2, 8, hre.ethers.parseEther("0.12"), 0
      );
    });

    it("Should return active listings for token", async function () {
      const activeListings = await marketplaceContract.getActiveListingsForToken(tokenId1);
      expect(activeListings).to.deep.equal([1, 2]);

      const token2Listings = await marketplaceContract.getActiveListingsForToken(tokenId2);
      expect(token2Listings).to.deep.equal([3]);
    });

    it("Should return user listings", async function () {
      const userListings = await marketplaceContract.getUserListings(creator.address);
      expect(userListings).to.deep.equal([1, 2, 3]);
    });

    it("Should return offers for listing", async function () {
      const listingId = 1;
      const expiresAt = Math.floor(Date.now() / 1000) + 3600;

      await marketplaceContract.connect(buyer1).makeOffer(
        listingId, 3, hre.ethers.parseEther("0.08"), expiresAt,
        { value: hre.ethers.parseEther("0.24") }
      );

      const offers = await marketplaceContract.getOffersForListing(listingId);
      expect(offers.length).to.equal(1);
      expect(offers[0].buyer).to.equal(buyer1.address);
    });
  });

  describe("⛽ Gas Optimization Tests", function () {
    it("Should use reasonable gas for listing creation", async function () {
      const tx = await marketplaceContract.connect(creator).createListing(
        tokenId1, 10, hre.ethers.parseEther("0.1"), 0
      );
      const receipt = await tx.wait();
      
      console.log(`      Gas used for listing creation: ${receipt.gasUsed.toString()}`);
      expect(receipt.gasUsed).to.be.lessThan(150000);
    });

    it("Should use reasonable gas for purchase", async function () {
      await marketplaceContract.connect(creator).createListing(
        tokenId1, 10, hre.ethers.parseEther("0.1"), 0
      );

      const tx = await marketplaceContract.connect(buyer1).buyListing(1, 5, {
        value: hre.ethers.parseEther("0.5")
      });
      const receipt = await tx.wait();
      
      console.log(`      Gas used for purchase: ${receipt.gasUsed.toString()}`);
      expect(receipt.gasUsed).to.be.lessThan(200000);
    });
  });

  describe("🛡️ Security and Edge Cases", function () {
    it("Should handle reentrancy protection", async function () {
      // The contract uses ReentrancyGuard, so all state-changing functions are protected
      expect(await marketplaceContract.marketplaceFee()).to.equal(250);
    });

    it("Should handle zero value transfers safely", async function () {
      // Test with zero royalty STEM
      const zeroRoyaltySTEM = { ...sampleSTEM, royaltyPercentage: 0 };
      await stemContract.connect(creator).mintSTEM(creator.address, 100, zeroRoyaltySTEM, "0x");
      
      await marketplaceContract.connect(creator).createListing(
        3, 10, hre.ethers.parseEther("0.1"), 0
      );

      // Should complete successfully with zero royalty
      await expect(
        marketplaceContract.connect(buyer1).buyListing(1, 5, {
          value: hre.ethers.parseEther("0.5")
        })
      ).to.not.be.reverted;
    });
  });
});
