// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title TellUrStoriSTEM - Optimized Version
 * @dev ERC1155 token contract for music STEM NFTs with enhanced security
 * @author TellUrStori V2 Team
 */
contract TellUrStoriSTEM is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard, Pausable, IERC2981 {
    using Strings for uint256;
    
    // STEM metadata structure
    struct STEMMetadata {
        string name;
        string description;
        string audioIPFSHash;
        string imageIPFSHash;
        address creator;
        uint256 createdAt;
        uint256 duration; // in seconds
        string genre;
        string[] tags;
        uint256 royaltyPercentage; // basis points (100 = 1%)
    }
    
    // Contract state
    mapping(uint256 => STEMMetadata) public stemMetadata;
    mapping(address => uint256[]) public creatorSTEMs;
    mapping(uint256 => address) public stemCreators;
    
    uint256 private _currentTokenId = 1;
    string private _baseMetadataURI;
    
    // Constants for validation
    uint256 public constant MAX_ROYALTY_PERCENTAGE = 5000; // 50%
    uint256 public constant MIN_DURATION = 1; // 1 second minimum
    uint256 public constant MAX_DURATION = 3600; // 1 hour maximum
    uint256 public constant MAX_TAGS = 10; // Maximum tags per STEM
    uint256 public constant MAX_BATCH_SIZE = 50; // Maximum batch mint size
    
    // Events
    event STEMMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string name,
        string audioIPFSHash,
        uint256 amount
    );
    
    event STEMMetadataUpdated(
        uint256 indexed tokenId,
        string name,
        string description
    );
    
    event RoyaltyPaid(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 amount
    );
    
    event ContractPaused(address indexed account);
    event ContractUnpaused(address indexed account);
    
    // Custom errors for gas efficiency
    error InvalidRoyaltyPercentage(uint256 provided, uint256 maximum);
    error InvalidDuration(uint256 provided, uint256 min, uint256 max);
    error EmptyName();
    error EmptyAudioHash();
    error InvalidIPFSHash(string hash);
    error TooManyTags(uint256 provided, uint256 maximum);
    error BatchSizeTooLarge(uint256 provided, uint256 maximum);
    error NotCreator(address caller, address creator);
    error TokenNotExists(uint256 tokenId);
    error ZeroAddress();
    
    constructor(
        string memory baseMetadataURI
    ) ERC1155("") Ownable(msg.sender) {
        if (bytes(baseMetadataURI).length == 0) revert EmptyName();
        _baseMetadataURI = baseMetadataURI;
    }
    
    /**
     * @dev Mint new STEM tokens with enhanced validation
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @param metadata STEM metadata
     * @param data Additional data for the mint
     * @return tokenId The ID of the newly minted token
     */
    function mintSTEM(
        address to,
        uint256 amount,
        STEMMetadata memory metadata,
        bytes memory data
    ) public nonReentrant whenNotPaused returns (uint256) {
        // Enhanced validation
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidDuration(amount, 1, type(uint256).max);
        if (bytes(metadata.name).length == 0) revert EmptyName();
        if (bytes(metadata.audioIPFSHash).length == 0) revert EmptyAudioHash();
        _validateIPFSHash(metadata.audioIPFSHash);
        if (metadata.royaltyPercentage > MAX_ROYALTY_PERCENTAGE) {
            revert InvalidRoyaltyPercentage(metadata.royaltyPercentage, MAX_ROYALTY_PERCENTAGE);
        }
        if (metadata.duration < MIN_DURATION || metadata.duration > MAX_DURATION) {
            revert InvalidDuration(metadata.duration, MIN_DURATION, MAX_DURATION);
        }
        if (metadata.tags.length > MAX_TAGS) {
            revert TooManyTags(metadata.tags.length, MAX_TAGS);
        }
        
        uint256 tokenId = _currentTokenId++;
        
        // Set metadata with caller as creator
        metadata.creator = msg.sender;
        metadata.createdAt = block.timestamp;
        stemMetadata[tokenId] = metadata;
        
        // Track creator's STEMs
        creatorSTEMs[msg.sender].push(tokenId);
        stemCreators[tokenId] = msg.sender;
        
        // Mint tokens
        _mint(to, tokenId, amount, data);
        
        emit STEMMinted(tokenId, msg.sender, metadata.name, metadata.audioIPFSHash, amount);
        
        return tokenId;
    }
    
    /**
     * @dev Batch mint multiple STEM tokens with gas optimization
     */
    function batchMintSTEMs(
        address to,
        uint256[] memory amounts,
        STEMMetadata[] memory metadataArray,
        bytes memory data
    ) public nonReentrant whenNotPaused returns (uint256[] memory) {
        if (to == address(0)) revert ZeroAddress();
        if (amounts.length != metadataArray.length) {
            revert InvalidDuration(amounts.length, metadataArray.length, metadataArray.length);
        }
        if (amounts.length == 0) revert InvalidDuration(0, 1, type(uint256).max);
        if (amounts.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(amounts.length, MAX_BATCH_SIZE);
        }
        
        uint256[] memory tokenIds = new uint256[](amounts.length);
        uint256[] memory ids = new uint256[](amounts.length);
        
        // Cache current token ID to save gas
        uint256 currentId = _currentTokenId;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokenId = currentId + i;
            tokenIds[i] = tokenId;
            ids[i] = tokenId;
            
            // Validation for each STEM
            STEMMetadata memory metadata = metadataArray[i];
            if (amounts[i] == 0) revert InvalidDuration(amounts[i], 1, type(uint256).max);
            if (bytes(metadata.name).length == 0) revert EmptyName();
            if (bytes(metadata.audioIPFSHash).length == 0) revert EmptyAudioHash();
            _validateIPFSHash(metadata.audioIPFSHash);
            if (metadata.royaltyPercentage > MAX_ROYALTY_PERCENTAGE) {
                revert InvalidRoyaltyPercentage(metadata.royaltyPercentage, MAX_ROYALTY_PERCENTAGE);
            }
            if (metadata.duration < MIN_DURATION || metadata.duration > MAX_DURATION) {
                revert InvalidDuration(metadata.duration, MIN_DURATION, MAX_DURATION);
            }
            if (metadata.tags.length > MAX_TAGS) {
                revert TooManyTags(metadata.tags.length, MAX_TAGS);
            }
            
            // Set metadata
            metadata.creator = msg.sender;
            metadata.createdAt = block.timestamp;
            stemMetadata[tokenId] = metadata;
            
            // Track creator's STEMs
            creatorSTEMs[msg.sender].push(tokenId);
            stemCreators[tokenId] = msg.sender;
            
            emit STEMMinted(tokenId, msg.sender, metadata.name, metadata.audioIPFSHash, amounts[i]);
        }
        
        // Update token ID counter once
        _currentTokenId = currentId + amounts.length;
        
        // Batch mint
        _mintBatch(to, ids, amounts, data);
        
        return tokenIds;
    }
    
    /**
     * @dev Update STEM metadata with enhanced security
     */
    function updateSTEMMetadata(
        uint256 tokenId,
        string memory name,
        string memory description
    ) public whenNotPaused {
        if (!exists(tokenId)) revert TokenNotExists(tokenId);
        if (stemCreators[tokenId] != msg.sender) {
            revert NotCreator(msg.sender, stemCreators[tokenId]);
        }
        if (bytes(name).length == 0) revert EmptyName();
        
        stemMetadata[tokenId].name = name;
        stemMetadata[tokenId].description = description;
        
        emit STEMMetadataUpdated(tokenId, name, description);
    }
    
    /**
     * @dev Get STEMs created by a specific address
     */
    function getSTEMsByCreator(address creator) external view returns (uint256[] memory) {
        return creatorSTEMs[creator];
    }
    
    /**
     * @dev Get STEM metadata with existence check
     */
    function getSTEMMetadata(uint256 tokenId) external view returns (STEMMetadata memory) {
        if (!exists(tokenId)) revert TokenNotExists(tokenId);
        return stemMetadata[tokenId];
    }
    
    /**
     * @dev ERC2981 royalty info implementation
     * @param tokenId Token ID to get royalty info for
     * @param salePrice Sale price to calculate royalty from
     * @return receiver Address to receive royalty payment
     * @return royaltyAmount Amount of royalty to pay
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        if (!exists(tokenId)) revert TokenNotExists(tokenId);
        
        receiver = stemCreators[tokenId];
        royaltyAmount = (salePrice * stemMetadata[tokenId].royaltyPercentage) / 10000;
        
        // Ensure royalty doesn't exceed sale price
        if (royaltyAmount > salePrice) {
            royaltyAmount = salePrice;
        }
    }
    
    /**
     * @dev Calculate royalty for a sale with overflow protection (legacy function)
     */
    function calculateRoyalty(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address creator, uint256 royaltyAmount) {
        if (!exists(tokenId)) revert TokenNotExists(tokenId);
        
        creator = stemCreators[tokenId];
        
        // Use safe math to prevent overflow
        uint256 royaltyPercentage = stemMetadata[tokenId].royaltyPercentage;
        royaltyAmount = (salePrice * royaltyPercentage) / 10000;
        
        // Ensure royalty doesn't exceed sale price
        if (royaltyAmount > salePrice) {
            royaltyAmount = salePrice;
        }
    }
    
    /**
     * @dev Get token URI with existence check
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!exists(tokenId)) revert TokenNotExists(tokenId);
        
        return string(abi.encodePacked(
            _baseMetadataURI,
            tokenId.toString(),
            ".json"
        ));
    }
    
    /**
     * @dev Set base metadata URI with validation
     */
    function setBaseMetadataURI(string memory baseMetadataURI) external onlyOwner {
        if (bytes(baseMetadataURI).length == 0) revert EmptyName();
        _baseMetadataURI = baseMetadataURI;
    }
    
    /**
     * @dev Get current token ID counter
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
    }
    
    /**
     * @dev Pause contract (emergency use only)
     */
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }
    
    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
    
    /**
     * @dev Validate IPFS hash format (supports multiple formats)
     * @param ipfsHash The IPFS hash to validate
     */
    function _validateIPFSHash(string memory ipfsHash) internal pure {
        bytes memory hashBytes = bytes(ipfsHash);
        
        // Support both CIDv0 (Qm...) and CIDv1 (bafy...) formats
        if (hashBytes.length == 46) {
            // CIDv0 format validation (Qm...)
            if (hashBytes[0] != 0x51 || hashBytes[1] != 0x6d) { // "Qm" in hex
                revert InvalidIPFSHash(ipfsHash);
            }
            
            // Validate base58 characters
            for (uint256 i = 2; i < hashBytes.length; i++) {
                if (!_isValidBase58Char(hashBytes[i])) {
                    revert InvalidIPFSHash(ipfsHash);
                }
            }
        } else if (hashBytes.length == 59) {
            // CIDv1 format validation (bafy...)
            if (hashBytes[0] != 0x62 || hashBytes[1] != 0x61 || 
                hashBytes[2] != 0x66 || hashBytes[3] != 0x79) { // "bafy" in hex
                revert InvalidIPFSHash(ipfsHash);
            }
            
            // Validate base32 characters for CIDv1
            for (uint256 i = 4; i < hashBytes.length; i++) {
                if (!_isValidBase32Char(hashBytes[i])) {
                    revert InvalidIPFSHash(ipfsHash);
                }
            }
        } else {
            revert InvalidIPFSHash(ipfsHash);
        }
    }
    
    /**
     * @dev Check if character is valid base58
     */
    function _isValidBase58Char(bytes1 char) internal pure returns (bool) {
        return (char >= 0x31 && char <= 0x39) || // 1-9
               (char >= 0x41 && char <= 0x48) || // A-H
               (char >= 0x4A && char <= 0x4E) || // J-N
               (char >= 0x50 && char <= 0x5A) || // P-Z
               (char >= 0x61 && char <= 0x6B) || // a-k
               (char >= 0x6D && char <= 0x7A);   // m-z
    }
    
    /**
     * @dev Check if character is valid base32 (for CIDv1)
     */
    function _isValidBase32Char(bytes1 char) internal pure returns (bool) {
        return (char >= 0x61 && char <= 0x7A) || // a-z
               (char >= 0x32 && char <= 0x37);   // 2-7
    }
    
    // Required overrides
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }
    
    /**
     * @dev Support for ERC165 interface detection
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
