// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./TellUrStoriSTEM.sol";

/**
 * @title STEMMarketplace - Optimized Version
 * @dev Enhanced marketplace for trading TellUrStori STEM NFTs with improved security
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
    
    // Offer structure with escrow
    struct Offer {
        uint256 listingId;
        address buyer;
        uint256 amount;
        uint256 pricePerToken;
        uint256 expiresAt;
        bool active;
        bool escrowed; // Track if payment is held in contract
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
    
    // Escrow for offers
    mapping(address => mapping(uint256 => uint256)) public escrowedOffers; // buyer => offerIndex => amount
    
    uint256 private _currentListingId = 1;
    uint256 private _currentAuctionId = 1;
    uint256 public marketplaceFee = 250; // 2.5% in basis points
    address public feeRecipient;
    
    // Constants
    uint256 public constant MAX_MARKETPLACE_FEE = 1000; // 10%
    uint256 public constant MIN_AUCTION_DURATION = 3600; // 1 hour
    uint256 public constant MAX_AUCTION_DURATION = 2592000; // 30 days
    uint256 public constant MIN_BID_INCREMENT = 500; // 5%
    uint256 public constant BID_EXTENSION_TIME = 300; // 5 minutes
    uint256 public constant BID_EXTENSION_THRESHOLD = 300; // 5 minutes before end
    
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
    
    event OfferWithdrawn(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount
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
    
    event AuctionExtended(
        uint256 indexed auctionId,
        uint256 newEndTime
    );
    
    event AuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );
    
    event MarketplaceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    
    // Events for failed operations (better UX)
    event OfferRejected(uint256 indexed listingId, uint256 indexed offerIndex, string reason);
    event BidFailed(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount, string reason);
    
    // Custom errors
    error InvalidPrice(uint256 price);
    error InvalidAmount(uint256 amount);
    error InvalidExpiration(uint256 expiration);
    error ListingNotActive(uint256 listingId);
    error ListingExpired(uint256 listingId);
    error InsufficientBalance(uint256 required, uint256 available);
    error NotApproved();
    error NotSeller(address caller, address seller);
    error NotBuyer(address caller, address buyer);
    error InsufficientPayment(uint256 required, uint256 provided);
    error AuctionNotActive(uint256 auctionId);
    error AuctionNotEnded(uint256 auctionId);
    error BidTooLow(uint256 required, uint256 provided);
    error AuctionAlreadySettled(uint256 auctionId);
    error InvalidDuration(uint256 duration, uint256 min, uint256 max);
    error ZeroAddress();
    error OfferNotActive(uint256 offerIndex);
    error TransferFailed();
    error FeePrecisionError(uint256 totalPrice, uint256 calculatedFee);
    
    constructor(
        address _stemContract,
        address _feeRecipient
    ) Ownable(msg.sender) {
        if (_stemContract == address(0) || _feeRecipient == address(0)) revert ZeroAddress();
        stemContract = TellUrStoriSTEM(_stemContract);
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev Create a new listing with enhanced validation
     */
    function createListing(
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    ) external returns (uint256) {
        if (pricePerToken == 0) revert InvalidPrice(pricePerToken);
        if (amount == 0) revert InvalidAmount(amount);
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidExpiration(expiresAt);
        
        uint256 balance = stemContract.balanceOf(msg.sender, tokenId);
        if (balance < amount) revert InsufficientBalance(amount, balance);
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
     * @dev Buy from a listing with improved payment security
     */
    function buyListing(uint256 listingId, uint256 amount) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        if (!listing.active) revert ListingNotActive(listingId);
        if (listing.expiresAt != 0 && block.timestamp > listing.expiresAt) {
            revert ListingExpired(listingId);
        }
        if (amount == 0 || amount > listing.amount) revert InvalidAmount(amount);
        
        uint256 totalPrice = amount * listing.pricePerToken;
        if (msg.value < totalPrice) revert InsufficientPayment(totalPrice, msg.value);
        
        // Calculate fees and royalties with precision check
        uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
        (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(listing.tokenId, totalPrice);
        
        // Ensure no underflow in fee calculations
        if (marketplaceFeeAmount + royaltyAmount > totalPrice) {
            revert FeePrecisionError(totalPrice, marketplaceFeeAmount + royaltyAmount);
        }
        
        uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
        
        // Transfer tokens first (CEI pattern)
        stemContract.safeTransferFrom(listing.seller, msg.sender, listing.tokenId, amount, "");
        
        // Update listing state
        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.active = false;
        }
        
        // Transfer payments with proper error handling
        _safeTransfer(payable(creator), royaltyAmount);
        _safeTransfer(payable(feeRecipient), marketplaceFeeAmount);
        _safeTransfer(payable(listing.seller), sellerAmount);
        
        // Refund excess payment
        if (msg.value > totalPrice) {
            _safeTransfer(payable(msg.sender), msg.value - totalPrice);
        }
        
        emit Sold(listingId, listing.tokenId, msg.sender, listing.seller, amount, totalPrice);
    }
    
    /**
     * @dev Cancel a listing
     */
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        
        if (listing.seller != msg.sender) revert NotSeller(msg.sender, listing.seller);
        if (!listing.active) revert ListingNotActive(listingId);
        
        listing.active = false;
        
        emit ListingCancelled(listingId, msg.sender);
    }
    
    /**
     * @dev Make an offer with escrow
     */
    function makeOffer(
        uint256 listingId,
        uint256 amount,
        uint256 pricePerToken,
        uint256 expiresAt
    ) external payable nonReentrant {
        if (pricePerToken == 0) revert InvalidPrice(pricePerToken);
        if (amount == 0) revert InvalidAmount(amount);
        if (expiresAt <= block.timestamp) revert InvalidExpiration(expiresAt);
        
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive(listingId);
        if (amount > listing.amount) revert InvalidAmount(amount);
        
        uint256 totalOfferAmount = amount * pricePerToken;
        if (msg.value < totalOfferAmount) revert InsufficientPayment(totalOfferAmount, msg.value);
        
        uint256 offerIndex = offers[listingId].length;
        
        offers[listingId].push(Offer({
            listingId: listingId,
            buyer: msg.sender,
            amount: amount,
            pricePerToken: pricePerToken,
            expiresAt: expiresAt,
            active: true,
            escrowed: true
        }));
        
        // Store escrowed amount
        escrowedOffers[msg.sender][offerIndex] = totalOfferAmount;
        
        userOffers[msg.sender].push(listingId);
        
        // Refund excess payment
        if (msg.value > totalOfferAmount) {
            _safeTransfer(payable(msg.sender), msg.value - totalOfferAmount);
        }
        
        emit OfferMade(listingId, msg.sender, amount, pricePerToken, expiresAt);
    }
    
    /**
     * @dev Accept an offer with improved security
     */
    function acceptOffer(uint256 listingId, uint256 offerIndex) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller(msg.sender, listing.seller);
        if (!listing.active) revert ListingNotActive(listingId);
        
        if (offerIndex >= offers[listingId].length) revert OfferNotActive(offerIndex);
        Offer storage offer = offers[listingId][offerIndex];
        
        if (!offer.active) revert OfferNotActive(offerIndex);
        if (block.timestamp > offer.expiresAt) revert ListingExpired(listingId);
        if (offer.amount > listing.amount) revert InvalidAmount(offer.amount);
        
        uint256 totalPrice = offer.amount * offer.pricePerToken;
        
        // Calculate fees and royalties with precision check
        uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
        (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(listing.tokenId, totalPrice);
        
        // Ensure no underflow in fee calculations
        if (marketplaceFeeAmount + royaltyAmount > totalPrice) {
            revert FeePrecisionError(totalPrice, marketplaceFeeAmount + royaltyAmount);
        }
        
        uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
        
        // Transfer tokens first (CEI pattern)
        stemContract.safeTransferFrom(msg.sender, offer.buyer, listing.tokenId, offer.amount, "");
        
        // Update states
        offer.active = false;
        offer.escrowed = false;
        listing.amount -= offer.amount;
        if (listing.amount == 0) {
            listing.active = false;
        }
        
        // Clear escrow
        escrowedOffers[offer.buyer][offerIndex] = 0;
        
        // Transfer payments from escrow
        _safeTransfer(payable(creator), royaltyAmount);
        _safeTransfer(payable(feeRecipient), marketplaceFeeAmount);
        _safeTransfer(payable(msg.sender), sellerAmount);
        
        emit OfferAccepted(listingId, offer.buyer, msg.sender, offer.amount, totalPrice);
    }
    
    /**
     * @dev Withdraw an offer and get refund
     */
    function withdrawOffer(uint256 listingId, uint256 offerIndex) external nonReentrant {
        if (offerIndex >= offers[listingId].length) revert OfferNotActive(offerIndex);
        Offer storage offer = offers[listingId][offerIndex];
        
        if (offer.buyer != msg.sender) revert NotBuyer(msg.sender, offer.buyer);
        if (!offer.active) revert OfferNotActive(offerIndex);
        if (block.timestamp <= offer.expiresAt) revert InvalidExpiration(offer.expiresAt);
        
        uint256 refundAmount = escrowedOffers[msg.sender][offerIndex];
        
        // Update states
        offer.active = false;
        offer.escrowed = false;
        escrowedOffers[msg.sender][offerIndex] = 0;
        
        // Refund escrowed amount
        if (refundAmount > 0) {
            _safeTransfer(payable(msg.sender), refundAmount);
        }
        
        emit OfferWithdrawn(listingId, msg.sender, refundAmount);
    }
    
    /**
     * @dev Reject an offer (seller only) - refunds buyer immediately
     */
    function rejectOffer(uint256 listingId, uint256 offerIndex, string calldata reason) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller(msg.sender, listing.seller);
        
        if (offerIndex >= offers[listingId].length) revert OfferNotActive(offerIndex);
        Offer storage offer = offers[listingId][offerIndex];
        
        if (!offer.active) revert OfferNotActive(offerIndex);
        
        uint256 refundAmount = escrowedOffers[offer.buyer][offerIndex];
        
        // Update states
        offer.active = false;
        offer.escrowed = false;
        escrowedOffers[offer.buyer][offerIndex] = 0;
        
        // Refund escrowed amount to buyer
        if (refundAmount > 0) {
            _safeTransfer(payable(offer.buyer), refundAmount);
        }
        
        emit OfferRejected(listingId, offerIndex, reason);
    }
    
    /**
     * @dev Create an auction with enhanced validation
     */
    function createAuction(
        uint256 tokenId,
        uint256 amount,
        uint256 startingPrice,
        uint256 duration
    ) external returns (uint256) {
        if (startingPrice == 0) revert InvalidPrice(startingPrice);
        if (amount == 0) revert InvalidAmount(amount);
        if (duration < MIN_AUCTION_DURATION || duration > MAX_AUCTION_DURATION) {
            revert InvalidDuration(duration, MIN_AUCTION_DURATION, MAX_AUCTION_DURATION);
        }
        
        uint256 balance = stemContract.balanceOf(msg.sender, tokenId);
        if (balance < amount) revert InsufficientBalance(amount, balance);
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
     * @dev Place a bid on an auction with improved security
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive(auctionId);
        if (block.timestamp >= auction.endTime) revert AuctionNotEnded(auctionId);
        
        uint256 minBid = auction.currentBid == 0 
            ? auction.startingPrice 
            : auction.currentBid + (auction.currentBid * MIN_BID_INCREMENT) / 10000;
            
        if (msg.value < minBid) revert BidTooLow(minBid, msg.value);
        
        // Anti-sniping: extend auction if bid placed near end
        if (block.timestamp > auction.endTime - BID_EXTENSION_THRESHOLD) {
            auction.endTime = block.timestamp + BID_EXTENSION_TIME;
            emit AuctionExtended(auctionId, auction.endTime);
        }
        
        // Refund previous bidder
        if (auction.currentBidder != address(0)) {
            _safeTransfer(payable(auction.currentBidder), auction.currentBid);
        }
        
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;
        
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }
    
    /**
     * @dev Settle an auction with enhanced security
     */
    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive(auctionId);
        if (block.timestamp < auction.endTime) revert AuctionNotEnded(auctionId);
        if (auction.settled) revert AuctionAlreadySettled(auctionId);
        
        auction.active = false;
        auction.settled = true;
        
        if (auction.currentBidder != address(0)) {
            // Calculate fees and royalties with precision check
            uint256 totalPrice = auction.currentBid;
            uint256 marketplaceFeeAmount = (totalPrice * marketplaceFee) / 10000;
            (address creator, uint256 royaltyAmount) = stemContract.calculateRoyalty(auction.tokenId, totalPrice);
            
            // Ensure no underflow in fee calculations
            if (marketplaceFeeAmount + royaltyAmount > totalPrice) {
                revert FeePrecisionError(totalPrice, marketplaceFeeAmount + royaltyAmount);
            }
            
            uint256 sellerAmount = totalPrice - marketplaceFeeAmount - royaltyAmount;
            
            // Transfer tokens to winner
            stemContract.safeTransferFrom(auction.seller, auction.currentBidder, auction.tokenId, auction.amount, "");
            
            // Transfer payments
            _safeTransfer(payable(creator), royaltyAmount);
            _safeTransfer(payable(feeRecipient), marketplaceFeeAmount);
            _safeTransfer(payable(auction.seller), sellerAmount);
            
            emit AuctionSettled(auctionId, auction.currentBidder, auction.currentBid);
        } else {
            // No bids, tokens remain with seller
            emit AuctionSettled(auctionId, address(0), 0);
        }
    }
    
    /**
     * @dev Safe transfer with proper error handling
     */
    function _safeTransfer(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @dev Set marketplace fee with validation and precision check
     */
    function setMarketplaceFee(uint256 _marketplaceFee) external onlyOwner {
        if (_marketplaceFee > MAX_MARKETPLACE_FEE) {
            revert InvalidPrice(_marketplaceFee);
        }
        
        uint256 oldFee = marketplaceFee;
        marketplaceFee = _marketplaceFee;
        
        emit MarketplaceFeeUpdated(oldFee, _marketplaceFee);
    }
    
    /**
     * @dev Set fee recipient with validation
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }
    
    /**
     * @dev Get active listings for a token (gas optimized with pagination)
     */
    function getActiveListingsForToken(uint256 tokenId) external view returns (uint256[] memory) {
        return getActiveListingsForTokenPaginated(tokenId, 0, 100); // Default: first 100 listings
    }
    
    /**
     * @dev Get active listings for a token with pagination
     * @param tokenId Token ID to get listings for
     * @param offset Starting index for pagination
     * @param limit Maximum number of listings to return
     */
    function getActiveListingsForTokenPaginated(
        uint256 tokenId, 
        uint256 offset, 
        uint256 limit
    ) public view returns (uint256[] memory) {
        if (limit == 0 || limit > 100) limit = 100; // Cap at 100 for gas safety
        
        uint256[] memory tempListings = new uint256[](limit);
        uint256 found = 0;
        uint256 skipped = 0;
        
        for (uint256 i = 1; i < _currentListingId && found < limit; i++) {
            if (listings[i].tokenId == tokenId && listings[i].active) {
                if (skipped >= offset) {
                    tempListings[found] = i;
                    found++;
                } else {
                    skipped++;
                }
            }
        }
        
        // Resize array to actual found count
        uint256[] memory activeListings = new uint256[](found);
        for (uint256 i = 0; i < found; i++) {
            activeListings[i] = tempListings[i];
        }
        
        return activeListings;
    }
    
    /**
     * @dev Get user's listings
     */
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }
    
    /**
     * @dev Get offers for a listing
     */
    function getOffersForListing(uint256 listingId) external view returns (Offer[] memory) {
        return offers[listingId];
    }
    
    /**
     * @dev Emergency function to recover stuck funds (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        _safeTransfer(payable(owner()), address(this).balance);
    }
    
    /**
     * @dev Prevent accidental ETH deposits - only allow through marketplace functions
     */
    receive() external payable {
        revert("Direct ETH transfers not allowed. Use marketplace functions.");
    }
}
