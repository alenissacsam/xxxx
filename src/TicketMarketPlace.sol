// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketMarketplace
 * @author alenissacsam
 * @dev marketplace with proper auction functionality and security fixes
 */
contract ImprovedTicketMarketplace is ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Marketplace__ItemNotListed(address tokenContract, uint256 tokenId);
    error Marketplace__InsufficientFunds(uint256 required, uint256 provided);
    error Marketplace__CannotBuyOwnItem();
    error Marketplace__PaymentFailed();
    error Marketplace__NotAuthorized();
    error Marketplace__InvalidTime();
    error Marketplace__AuctionEnded();
    error Marketplace__AuctionActive();
    error Marketplace__NoActiveBids();
    error Marketplace__BidTooLow();

    /*//////////////////////////////////////////////////////////////
                               ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/
    enum SaleType {
        FIXED_PRICE,
        AUCTION
    }
    enum AuctionStatus {
        ACTIVE,
        ENDED,
        CANCELLED
    }

    struct Listing {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 price; // Starting price for auctions, fixed price for sales
        SaleType saleType;
        bool active;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        address highestBidder;
        uint256 highestBid;
        AuctionStatus status;
        mapping(address => uint256) bids; // Track all bids for refunds
        address[] bidders; // Track bidder addresses
    }

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Auction) public auctions;
    mapping(address => uint256) public tokenContractVolume;
    mapping(uint256 => uint256) public dailyVolume;

    // Packed struct for gas optimization
    struct PlatformConfig {
        uint128 platformFeePercent; // 2.5% = 250
        uint128 maxAuctionDuration; // Maximum auction duration
    }

    PlatformConfig public config;
    address public immutable PLATFORM_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Listed(
        address indexed seller,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 price,
        SaleType saleType
    );

    event AuctionCreated(
        bytes32 indexed listingId,
        uint256 startTime,
        uint256 endTime,
        uint256 reservePrice
    );

    event BidPlaced(
        bytes32 indexed listingId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );

    event AuctionSettled(
        bytes32 indexed listingId,
        address indexed winner,
        uint256 finalPrice
    );

    event ListingCancelled(bytes32 indexed listingId, address indexed seller);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _platformAddress,
        uint128 _platformFeePercent
    ) Ownable(msg.sender) {
        PLATFORM_ADDRESS = _platformAddress;
        config = PlatformConfig({
            platformFeePercent: _platformFeePercent,
            maxAuctionDuration: 30 days
        });
    }

    /*//////////////////////////////////////////////////////////////
                            LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Lists an item for fixed price sale
     */
    function listItemFixedPrice(
        address tokenContract,
        uint256 tokenId,
        uint256 price
    ) external {
        _validateListing(tokenContract, tokenId);

        bytes32 listingId = getListingId(tokenContract, tokenId);

        listings[listingId] = Listing({
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: price,
            saleType: SaleType.FIXED_PRICE,
            active: true
        });

        emit Listed(
            msg.sender,
            tokenContract,
            tokenId,
            price,
            SaleType.FIXED_PRICE
        );
    }

    /**
     * @dev Creates an auction listing
     */
    function createAuction(
        address tokenContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 minBidIncrement
    ) external {
        if (duration > config.maxAuctionDuration)
            revert Marketplace__InvalidTime();

        _validateListing(tokenContract, tokenId);

        bytes32 listingId = getListingId(tokenContract, tokenId);

        // Create listing
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: startingPrice,
            saleType: SaleType.AUCTION,
            active: true
        });

        // Create auction
        Auction storage auction = auctions[listingId];
        auction.startTime = block.timestamp;
        auction.endTime = block.timestamp + duration;
        auction.reservePrice = reservePrice;
        auction.minBidIncrement = minBidIncrement;
        auction.status = AuctionStatus.ACTIVE;

        emit Listed(
            msg.sender,
            tokenContract,
            tokenId,
            startingPrice,
            SaleType.AUCTION
        );
        emit AuctionCreated(
            listingId,
            auction.startTime,
            auction.endTime,
            reservePrice
        );
    }

    /**
     * @dev Cancel a listing (only by seller)
     */
    function cancelListing(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (listing.seller != msg.sender) revert Marketplace__NotAuthorized();

        // If it's an auction with active bids, refund bidders
        if (listing.saleType == SaleType.AUCTION) {
            Auction storage auction = auctions[listingId];
            if (auction.highestBidder != address(0)) {
                _refundAllBidders(listingId);
            }
            auction.status = AuctionStatus.CANCELLED;
        }

        listing.active = false;
        emit ListingCancelled(listingId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            BUYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Buy fixed price item
     */
    function buyItem(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (listing.saleType != SaleType.FIXED_PRICE)
            revert Marketplace__InvalidTime();
        if (msg.value < listing.price)
            revert Marketplace__InsufficientFunds(listing.price, msg.value);
        if (msg.sender == listing.seller)
            revert Marketplace__CannotBuyOwnItem();

        listing.active = false;

        _executeTransfer(listingId, msg.sender, msg.value);
    }

    /**
     * @dev Place bid on auction
     */
    function placeBid(
        address tokenContract,
        uint256 tokenId
    ) external payable nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (listing.saleType != SaleType.AUCTION)
            revert Marketplace__InvalidTime();
        if (listing.seller == msg.sender)
            revert Marketplace__CannotBuyOwnItem();

        Auction storage auction = auctions[listingId];

        if (block.timestamp >= auction.endTime)
            revert Marketplace__AuctionEnded();
        if (auction.status != AuctionStatus.ACTIVE)
            revert Marketplace__AuctionEnded();

        uint256 minBid = auction.highestBid + auction.minBidIncrement;
        if (auction.highestBid == 0) {
            minBid = listing.price; // Starting price
        }

        if (msg.value < minBid) revert Marketplace__BidTooLow();

        // Refund previous highest bidder
        if (auction.highestBidder != address(0)) {
            _refundBidder(auction.highestBidder, auction.highestBid);
        } else {
            // First bid, add to bidders array
            auction.bidders.push(msg.sender);
        }

        // Update auction state
        if (auction.bids[msg.sender] == 0) {
            auction.bidders.push(msg.sender);
        }
        auction.bids[msg.sender] = msg.value;
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(listingId, msg.sender, msg.value, block.timestamp);

        // Auto-extend auction if bid placed in last 10 minutes
        if (auction.endTime - block.timestamp < 600) {
            // 10 minutes
            auction.endTime += 600; // Extend by 10 minutes
        }
    }

    /**
     * @dev Settle completed auction
     */
    function settleAuction(
        address tokenContract,
        uint256 tokenId
    ) external nonReentrant {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Listing storage listing = listings[listingId];
        Auction storage auction = auctions[listingId];

        if (!listing.active)
            revert Marketplace__ItemNotListed(tokenContract, tokenId);
        if (auction.status != AuctionStatus.ACTIVE)
            revert Marketplace__AuctionEnded();
        if (block.timestamp < auction.endTime)
            revert Marketplace__AuctionActive();

        listing.active = false;
        auction.status = AuctionStatus.ENDED;

        if (
            auction.highestBidder == address(0) ||
            auction.highestBid < auction.reservePrice
        ) {
            // No bids or reserve not met - return item to seller
            if (auction.highestBidder != address(0)) {
                _refundBidder(auction.highestBidder, auction.highestBid);
            }
            emit AuctionSettled(listingId, address(0), 0);
            return;
        }

        // Successful auction
        _executeTransfer(listingId, auction.highestBidder, auction.highestBid);
        emit AuctionSettled(
            listingId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateListing(
        address tokenContract,
        uint256 tokenId
    ) internal view {
        if (IERC721(tokenContract).ownerOf(tokenId) != msg.sender) {
            revert Marketplace__NotAuthorized();
        }
        if (
            !IERC721(tokenContract).isApprovedForAll(msg.sender, address(this))
        ) {
            revert Marketplace__NotAuthorized();
        }
    }

    function _executeTransfer(
        bytes32 listingId,
        address buyer,
        uint256 amount
    ) internal {
        Listing memory listing = listings[listingId];

        // Calculate fees
        (address royaltyRecipient, uint256 royaltyAmount) = IERC2981(
            listing.tokenContract
        ).royaltyInfo(listing.tokenId, amount);

        uint256 platformFee = (amount * config.platformFeePercent) / 10000;
        uint256 sellerAmount = amount - platformFee - royaltyAmount;

        // Transfer NFT
        IERC721(listing.tokenContract).transferFrom(
            listing.seller,
            buyer,
            listing.tokenId
        );

        // Distribute payments using call pattern
        _safeTransfer(payable(listing.seller), sellerAmount);
        _safeTransfer(payable(PLATFORM_ADDRESS), platformFee);

        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            _safeTransfer(payable(royaltyRecipient), royaltyAmount);
        }

        // Track volume
        tokenContractVolume[listing.tokenContract] += amount;
        dailyVolume[block.timestamp / 1 days] += amount;
    }

    function _safeTransfer(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert Marketplace__PaymentFailed();
    }

    function _refundBidder(address bidder, uint256 amount) internal {
        _safeTransfer(payable(bidder), amount);
    }

    function _refundAllBidders(bytes32 listingId) internal {
        Auction storage auction = auctions[listingId];

        for (uint256 i = 0; i < auction.bidders.length; i++) {
            address bidder = auction.bidders[i];
            uint256 bidAmount = auction.bids[bidder];
            if (bidAmount > 0) {
                auction.bids[bidder] = 0;
                _refundBidder(bidder, bidAmount);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getListingId(
        address tokenContract,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenContract, tokenId));
    }

    function getAuctionInfo(
        address tokenContract,
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 reservePrice,
            address highestBidder,
            uint256 highestBid,
            AuctionStatus status
        )
    {
        bytes32 listingId = getListingId(tokenContract, tokenId);
        Auction storage auction = auctions[listingId];

        return (
            auction.startTime,
            auction.endTime,
            auction.reservePrice,
            auction.highestBidder,
            auction.highestBid,
            auction.status
        );
    }

    function getTodaysVolume() external view returns (uint256) {
        return dailyVolume[block.timestamp / 1 days];
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updatePlatformFee(uint128 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        config.platformFeePercent = newFee;
    }

    function emergencyWithdraw() external onlyOwner {
        _safeTransfer(payable(owner()), address(this).balance);
    }
}
