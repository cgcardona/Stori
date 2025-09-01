// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./TellUrStoriSTEM.sol";

/**
 * @title STEMMarketplace
 * @dev Marketplace for trading TellUrStori STEM NFTs with royalty support
 * @author TellUrStori V2 Team
 */
contract STEMMarketplace is ReentrancyGuard, Ownable, ERC1155Holder {
    
    // Listing structure
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 amount;
        uint256 pricePerToken;
        bool active;
        uint256 listedAt;
        uint256 expiresAt; // 0 = no expiration
    }
    
    // Offer structure
    struct Offer {
        uint256 listingId;
        address buyer;
        uint256 amount;
        uint256 pricePerToken;
        uint256 expiresAt;
        bool active;
    }
    
    // Auction structure
    struct Auction {
        uint256 tokenId;
        address seller;
        uint256 amount;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 startTime;
        uint256 endTime;
        bool active;
        bool settled;
    }
    
    // Contract state
    TellUrStoriSTEM public immutable stemContract;
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer[]) public offers;
    mapping(uint256 => Auction) public auctions;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userOffers;
    mapping(address => uint256[]) public userAuctions;
    
    uint256 private _currentListingId = 1;
    uint256 private _currentAuctionId = 1;
    uint256 public marketplaceFee = 250; // 2.5% in basis points
    address public feeRecipient;
    
    // Events
    event Listed(
        uint256 indexed listingId,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    );
    
    event Sold(
        uint256 indexed listingId,
        uint256 indexed tokenId,
        address indexed buyer,
        address seller,
        uint256 amount,
        uint256 totalPrice
    );
    
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed seller
    );
    
    event OfferMade(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    );
    
    event OfferAccepted(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 totalPrice
    );
    
    event AuctionCreated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 amount,
        uint256 startingPrice,
        uint256 endTime
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );
    
    event AuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );
    
    // Custom errors
    error InvalidPrice();
    error InvalidAmount();
    error InvalidExpiration();
    error ListingNotActive();
    error ListingExpired();
    error InsufficientBalance();
    error NotApproved();
    error NotSeller();
    error NotBuyer();
    error InsufficientPayment();
    error AuctionNotActive();
    error AuctionNotEnded();
    error BidTooLow();
    error AuctionAlreadySettled();
    
    constructor(
        address _stemContract,
        address _feeRecipient
    ) Ownable(msg.sender) {
        stemContract = TellUrStoriSTEM(_stemContract);
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev Create a new listing
     * @param tokenId Token ID to list
     * @param amount Amount of tokens to list
     * @param pricePerToken Price per token in wei
     * @param expiresAt Expiration timestamp (0 for no expiration)
     * @return listingId The ID of the created listing
     */
    function createListing(
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    ) external returns (uint256) {
        if (pricePerToken == 0) revert InvalidPrice();
        if (amount == 0) revert InvalidAmount();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidExpiration();
        if (stemContract.balanceOf(msg.sender, tokenId) < amount) revert InsufficientBalance();
        if (!stemContract.isApprovedForAll(msg.sender, address(this))) revert NotApproved();
        
        uint256 listingId = _currentListingId++;
        
        listings[listingId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            amount: amount,
            pricePerToken: pricePerToken,
            active: true,
            listedAt: block.timestamp,
            expiresAt: expiresAt
        });
        
        userListings[msg.sender].push(listingId);
        
        emit Listed(listingId, tokenId, msg.sender, amount, pricePerToken, expiresAt);
        
        return listingId;
    }
    
    /**
     * @dev Buy from a listing
     * @param listingId Listing ID to buy from
     * @param amount Amount of tokens to buy
     */
    function buyListing(uint256 listingId, uint256 amount) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        if (!listing.active) revert ListingNotActive();
        if (listing.expiresAt != 0 && block.timestamp > listing.expiresAt) revert ListingExpired();
        if (amount == 0 || amount > listing.amount) revert InvalidAmount();
        
        uint256 totalPrice = amount * listing.pricePerToken;
        if (msg.value < totalPrice) revert InsufficientPayment();
        
        // Calculate fees and royalties
        uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
        
        // Get royalty info
        (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(listing.tokenId, totalPrice);
        
        uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
        
        // Transfer tokens
        stemContract.safeTransferFrom(listing.seller, msg.sender, listing.tokenId, amount, "");
        
        // Transfer payments
        if (royaltyAmount > 0) {
            payable(creator).transfer(royaltyAmount);
        }
        payable(feeRecipient).transfer(marketplaceFeeAmount);
        payable(listing.seller).transfer(sellerAmount);
        
        // Refund excess payment
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
        
        // Update listing
        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.active = false;
        }
        
        emit Sold(listingId, listing.tokenId, msg.sender, listing.seller, amount, totalPrice);
    }
    
    /**
     * @dev Cancel a listing
     * @param listingId Listing ID to cancel
     */
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();
        
        listing.active = false;
        
        emit ListingCancelled(listingId, msg.sender);
    }
    
    /**
     * @dev Make an offer on a listing
     * @param listingId Listing ID to make offer on
     * @param amount Amount of tokens to offer for
     * @param pricePerToken Price per token offered
     * @param expiresAt Offer expiration timestamp
     */
    function makeOffer(
        uint256 listingId,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    ) external payable {
        if (pricePerToken == 0) revert InvalidPrice();
        if (amount == 0) revert InvalidAmount();
        if (expiresAt <= block.timestamp) revert InvalidExpiration();
        
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (amount > listing.amount) revert InvalidAmount();
        
        uint256 totalOfferAmount = amount * pricePerToken;
        if (msg.value < totalOfferAmount) revert InsufficientPayment();
        
        offers[listingId].push(Offer({
            listingId: listingId,
            buyer: msg.sender,
            amount: amount,
            pricePerToken: pricePerToken,
            expiresAt: expiresAt,
            active: true
        }));
        
        userOffers[msg.sender].push(listingId);
        
        emit OfferMade(listingId, msg.sender, amount, pricePerToken, expiresAt);
    }
    
    /**
     * @dev Accept an offer
     * @param listingId Listing ID
     * @param offerIndex Index of the offer to accept
     */
    function acceptOffer(uint256 listingId, uint256 offerIndex) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();
        
        Offer storage offer = offers[listingId][offerIndex];
        if (!offer.active) revert ListingNotActive();
        if (block.timestamp > offer.expiresAt) revert ListingExpired();
        if (offer.amount > listing.amount) revert InvalidAmount();
        
        uint256 totalPrice = offer.amount * offer.pricePerToken;
        
        // Calculate fees and royalties
        uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
        (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(listing.tokenId, totalPrice);
        uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
        
        // Transfer tokens
        stemContract.safeTransferFrom(msg.sender, offer.buyer, listing.tokenId, offer.amount, "");
        
        // Transfer payments (offer payment is held in contract)
        if (royaltyAmount > 0) {
            payable(creator).transfer(royaltyAmount);
        }
        payable(feeRecipient).transfer(marketplaceFeeAmount);
        payable(msg.sender).transfer(sellerAmount);
        
        // Update states
        offer.active = false;
        listing.amount -= offer.amount;
        if (listing.amount == 0) {
            listing.active = false;
        }
        
        emit OfferAccepted(listingId, offer.buyer, msg.sender, offer.amount, totalPrice);
    }
    
    /**
     * @dev Create an auction
     * @param tokenId Token ID to auction
     * @param amount Amount of tokens to auction
     * @param startingPrice Starting bid price
     * @param duration Auction duration in seconds
     * @return auctionId The ID of the created auction
     */
    function createAuction(
        uint256 tokenId,
        uint256 amount,
        uint256 startingPrice,
        uint256 duration
    ) external returns (uint256) {
        if (startingPrice == 0) revert InvalidPrice();
        if (amount == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidExpiration();
        if (stemContract.balanceOf(msg.sender, tokenId) < amount) revert InsufficientBalance();
        if (!stemContract.isApprovedForAll(msg.sender, address(this))) revert NotApproved();
        
        uint256 auctionId = _currentAuctionId++;
        uint256 endTime = block.timestamp + duration;
        
        auctions[auctionId] = Auction({
            tokenId: tokenId,
            seller: msg.sender,
            amount: amount,
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            startTime: block.timestamp,
            endTime: endTime,
            active: true,
            settled: false
        });
        
        userAuctions[msg.sender].push(auctionId);
        
        emit AuctionCreated(auctionId, tokenId, msg.sender, amount, startingPrice, endTime);
        
        return auctionId;
    }
    
    /**
     * @dev Place a bid on an auction
     * @param auctionId Auction ID to bid on
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive();
        if (block.timestamp >= auction.endTime) revert AuctionNotEnded();
        
        uint256 minBid = auction.currentBid == 0 ? auction.startingPrice : auction.currentBid + (auction.currentBid / 20); // 5% increase
        if (msg.value < minBid) revert BidTooLow();
        
        // Refund previous bidder
        if (auction.currentBidder != address(0)) {
            payable(auction.currentBidder).transfer(auction.currentBid);
        }
        
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;
        
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }
    
    /**
     * @dev Settle an auction
     * @param auctionId Auction ID to settle
     */
    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive();
        if (block.timestamp < auction.endTime) revert AuctionNotEnded();
        if (auction.settled) revert AuctionAlreadySettled();
        
        auction.active = false;
        auction.settled = true;
        
        if (auction.currentBidder != address(0)) {
            // Calculate fees and royalties
            uint256 totalPrice = auction.currentBid;
            uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
            (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(auction.tokenId, totalPrice);
            uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
            
            // Transfer tokens to winner
            stemContract.safeTransferFrom(auction.seller, auction.currentBidder, auction.tokenId, auction.amount, "");
            
            // Transfer payments
            if (royaltyAmount > 0) {
                payable(creator).transfer(royaltyAmount);
            }
            payable(feeRecipient).transfer(marketplaceFeeAmount);
            payable(auction.seller).transfer(sellerAmount);
            
            emit AuctionSettled(auctionId, auction.currentBidder, auction.currentBid);
        } else {
            // No bids, return tokens to seller (they remain with seller)
            emit AuctionSettled(auctionId, address(0), 0);
        }
    }
    
    /**
     * @dev Set marketplace fee (only owner)
     * @param _marketplaceFee New marketplace fee in basis points
     */
    function setMarketplaceFee(uint256 _marketplaceFee) external onlyOwner {
        require(_marketplaceFee <= 1000, "Fee too high"); // Max 10%
        marketplaceFee = _marketplaceFee;
    }
    
    /**
     * @dev Set fee recipient (only owner)
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid address");
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev Get active listings for a token
     * @param tokenId Token ID
     * @return Array of active listing IDs
     */
    function getActiveListingsForToken(uint256 tokenId) external view returns (uint256[] memory) {
        uint256[] memory allListings = new uint256[](_currentListingId - 1);
        uint256 count = 0;
        
        for (uint256 i = 1; i < _currentListingId; i++) {
            if (listings[i].tokenId == tokenId && listings[i].active) {
                allListings[count] = i;
                count++;
            }
        }
        
        // Resize array
        uint256[] memory activeListings = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            activeListings[i] = allListings[i];
        }
        
        return activeListings;
    }
    
    /**
     * @dev Get user's listings
     * @param user User address
     * @return Array of listing IDs
     */
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }
    
    /**
     * @dev Get offers for a listing
     * @param listingId Listing ID
     * @return Array of offers
     */
    function getOffersForListing(uint256 listingId) external view returns (Offer[] memory) {
        return offers[listingId];
    }
}
