// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketMarketplace
 * @author alenissacsam
 * @dev A smart contract for managing a marketplace for event tickets.
 */

contract TicketMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }
    
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 expiry;
    }
    
    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Bid[]) public tokenBids;
    mapping(bytes32 => uint256) public highestBid;
    
    // Trading volume tracking for trending
    mapping(address => uint256) public tokenContractVolume;
    mapping(uint256 => uint256) public dailyVolume; // day => volume
    
    uint256 public platformFeePercent = 250; // 2.5%
    address public platformAddress;
    
    event Listed(address indexed seller, address indexed tokenContract, uint256 indexed tokenId, uint256 price);
    event Sold(address indexed buyer, address indexed seller, address indexed tokenContract, uint256 tokenId, uint256 price);
    event BidPlaced(address indexed bidder, address indexed tokenContract, uint256 indexed tokenId, uint256 amount);
    event BidAccepted(address indexed seller, address indexed bidder, address indexed tokenContract, uint256 tokenId, uint256 amount);
    
    constructor(address _platformAddress) Ownable(msg.sender){
        platformAddress = _platformAddress;
    }
    
    function listItem(address tokenContract, uint256 tokenId, uint256 price) external {
        require(IERC721(tokenContract).ownerOf(tokenId) == msg.sender, "Not owner");
        require(IERC721(tokenContract).isApprovedForAll(msg.sender, address(this)), "Not approved");
        
        bytes32 listingId = keccak256(abi.encodePacked(tokenContract, tokenId));
        
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: price,
            active: true
        });
        
        emit Listed(msg.sender, tokenContract, tokenId, price);
    }
    
    function buyItem(address tokenContract, uint256 tokenId) external payable nonReentrant {
        bytes32 listingId = keccak256(abi.encodePacked(tokenContract, tokenId));
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Item not listed");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy own item");
        
        listing.active = false;
        
        // Handle royalties
        uint256 royaltyAmount = 0;
        address royaltyRecipient = address(0);
        
        if (IERC165(tokenContract).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyRecipient, royaltyAmount) = IERC2981(tokenContract).royaltyInfo(tokenId, msg.value);
        }
        
        // Calculate fees
        uint256 platformFee = (msg.value * platformFeePercent) / 10000;
        uint256 sellerAmount = msg.value - platformFee - royaltyAmount;
        
        // Transfer NFT
        IERC721(tokenContract).transferFrom(listing.seller, msg.sender, tokenId);
        
        // Distribute payments
        payable(listing.seller).transfer(sellerAmount);
        payable(platformAddress).transfer(platformFee);
        
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            payable(royaltyRecipient).transfer(royaltyAmount);
        }
        
        // Track volume for trending
        tokenContractVolume[tokenContract] += msg.value;
        uint256 today = block.timestamp / 1 days;
        dailyVolume[today] += msg.value;
        
        emit Sold(msg.sender, listing.seller, tokenContract, tokenId, msg.value);
    }
    
    function placeBid(address tokenContract, uint256 tokenId, uint256 expiry) external payable {
        require(msg.value > 0, "Bid must be greater than 0");
        require(expiry > block.timestamp, "Expiry must be in future");
        
        bytes32 listingId = keccak256(abi.encodePacked(tokenContract, tokenId));
        
        tokenBids[listingId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            expiry: expiry
        }));
        
        if (msg.value > highestBid[listingId]) {
            highestBid[listingId] = msg.value;
        }
        
        emit BidPlaced(msg.sender, tokenContract, tokenId, msg.value);
    }
    
    function acceptBid(address tokenContract, uint256 tokenId, uint256 bidIndex) external nonReentrant {
        bytes32 listingId = keccak256(abi.encodePacked(tokenContract, tokenId));
        require(IERC721(tokenContract).ownerOf(tokenId) == msg.sender, "Not owner");
        
        Bid storage bid = tokenBids[listingId][bidIndex];
        require(bid.expiry > block.timestamp, "Bid expired");
        require(bid.amount > 0, "Invalid bid");
        
        uint256 amount = bid.amount;
        address bidder = bid.bidder;
        
        // Clear the bid
        bid.amount = 0;
        
        // Handle royalties and fees (similar to buyItem)
        uint256 royaltyAmount = 0;
        address royaltyRecipient = address(0);
        
        if (IERC165(tokenContract).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyRecipient, royaltyAmount) = IERC2981(tokenContract).royaltyInfo(tokenId, amount);
        }
        
        uint256 platformFee = (amount * platformFeePercent) / 10000;
        uint256 sellerAmount = amount - platformFee - royaltyAmount;
        
        // Transfer NFT
        IERC721(tokenContract).transferFrom(msg.sender, bidder, tokenId);
        
        // Distribute payments
        payable(msg.sender).transfer(sellerAmount);
        payable(platformAddress).transfer(platformFee);
        
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            payable(royaltyRecipient).transfer(royaltyAmount);
        }
        
        // Track volume
        tokenContractVolume[tokenContract] += amount;
        uint256 today = block.timestamp / 1 days;
        dailyVolume[today] += amount;
        
        emit BidAccepted(msg.sender, bidder, tokenContract, tokenId, amount);
    }
    
    // View functions for trending data
    function getTokenVolume(address tokenContract) external view returns (uint256) {
        return tokenContractVolume[tokenContract];
    }
    
    function getDailyVolume(uint256 day) external view returns (uint256) {
        return dailyVolume[day];
    }
    
    function getTodaysVolume() external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyVolume[today];
    }
}
