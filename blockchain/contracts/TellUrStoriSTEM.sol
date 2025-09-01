// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TellUrStoriSTEM
 * @dev ERC1155 token contract for music STEM NFTs with royalty support
 * @author TellUrStori V2 Team
 */
contract TellUrStoriSTEM is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard {
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
    
    // Custom errors
    error InvalidRoyaltyPercentage();
    error InvalidDuration();
    error EmptyName();
    error EmptyAudioHash();
    error NotCreator();
    error TokenNotExists();
    
    constructor(
        string memory baseMetadataURI
    ) ERC1155("") Ownable(msg.sender) {
        _baseMetadataURI = baseMetadataURI;
    }
    
    /**
     * @dev Mint new STEM tokens
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
    ) public returns (uint256) {
        // Validation
        if (bytes(metadata.name).length == 0) revert EmptyName();
        if (bytes(metadata.audioIPFSHash).length == 0) revert EmptyAudioHash();
        if (metadata.royaltyPercentage > 5000) revert InvalidRoyaltyPercentage(); // Max 50%
        if (metadata.duration == 0) revert InvalidDuration();
        
        uint256 tokenId = _currentTokenId++;
        
        // Set metadata
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
     * @dev Batch mint multiple STEM tokens
     * @param to Address to mint tokens to
     * @param amounts Array of amounts for each token
     * @param metadataArray Array of STEM metadata
     * @param data Additional data for the mint
     * @return tokenIds Array of newly minted token IDs
     */
    function batchMintSTEMs(
        address to,
        uint256[] memory amounts,
        STEMMetadata[] memory metadataArray,
        bytes memory data
    ) public returns (uint256[] memory) {
        require(amounts.length == metadataArray.length, "Arrays length mismatch");
        
        uint256[] memory tokenIds = new uint256[](amounts.length);
        uint256[] memory ids = new uint256[](amounts.length);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokenId = _currentTokenId++;
            tokenIds[i] = tokenId;
            ids[i] = tokenId;
            
            // Validation
            STEMMetadata memory metadata = metadataArray[i];
            if (bytes(metadata.name).length == 0) revert EmptyName();
            if (bytes(metadata.audioIPFSHash).length == 0) revert EmptyAudioHash();
            if (metadata.royaltyPercentage > 5000) revert InvalidRoyaltyPercentage();
            if (metadata.duration == 0) revert InvalidDuration();
            
            // Set metadata
            metadata.creator = msg.sender;
            metadata.createdAt = block.timestamp;
            stemMetadata[tokenId] = metadata;
            
            // Track creator's STEMs
            creatorSTEMs[msg.sender].push(tokenId);
            stemCreators[tokenId] = msg.sender;
            
            emit STEMMinted(tokenId, msg.sender, metadata.name, metadata.audioIPFSHash, amounts[i]);
        }
        
        // Batch mint
        _mintBatch(to, ids, amounts, data);
        
        return tokenIds;
    }
    
    /**
     * @dev Update STEM metadata (only creator)
     * @param tokenId Token ID to update
     * @param name New name
     * @param description New description
     */
    function updateSTEMMetadata(
        uint256 tokenId,
        string memory name,
        string memory description
    ) public {
        if (!exists(tokenId)) revert TokenNotExists();
        if (stemCreators[tokenId] != msg.sender) revert NotCreator();
        if (bytes(name).length == 0) revert EmptyName();
        
        stemMetadata[tokenId].name = name;
        stemMetadata[tokenId].description = description;
        
        emit STEMMetadataUpdated(tokenId, name, description);
    }
    
    /**
     * @dev Get STEMs created by a specific address
     * @param creator Creator address
     * @return Array of token IDs created by the address
     */
    function getSTEMsByCreator(address creator) external view returns (uint256[] memory) {
        return creatorSTEMs[creator];
    }
    
    /**
     * @dev Get STEM metadata
     * @param tokenId Token ID
     * @return STEM metadata struct
     */
    function getSTEMMetadata(uint256 tokenId) external view returns (STEMMetadata memory) {
        if (!exists(tokenId)) revert TokenNotExists();
        return stemMetadata[tokenId];
    }
    
    /**
     * @dev Calculate royalty for a sale
     * @param tokenId Token ID
     * @param salePrice Sale price
     * @return creator Creator address
     * @return royaltyAmount Royalty amount to pay
     */
    function calculateRoyalty(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address creator, uint256 royaltyAmount) {
        if (!exists(tokenId)) revert TokenNotExists();
        
        creator = stemCreators[tokenId];
        royaltyAmount = (salePrice * stemMetadata[tokenId].royaltyPercentage) / 10000;
    }
    
    /**
     * @dev Get token URI for metadata
     * @param tokenId Token ID
     * @return Token URI string
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!exists(tokenId)) revert TokenNotExists();
        
        return string(abi.encodePacked(
            _baseMetadataURI,
            tokenId.toString(),
            ".json"
        ));
    }
    
    /**
     * @dev Set base metadata URI (only owner)
     * @param baseMetadataURI New base URI
     */
    function setBaseMetadataURI(string memory baseMetadataURI) external onlyOwner {
        _baseMetadataURI = baseMetadataURI;
    }
    
    /**
     * @dev Get current token ID counter
     * @return Current token ID
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
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
        override(ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
