// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ERC721URIStorage,ERC721,IERC165} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {UserVerification} from "./UserVerification.sol";

/**
 * @title EventTicket
 * @author alenissacsam
 * @dev A smart contract for Creating event tickets.
 */
contract EventTicket is ERC721URIStorage, IERC2981, ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error EventTicket__UserNotVerified();
    error EventTicket__mintCooldown(address user, uint256 lastMintTime);
    error EventTicket__ZeroAddressNotAllowed();
    error EventTicket__InvalidOrganizerPercentage(uint256 percentage);
    error EventTicket__OrganizerPaymentFailed();
    error EventTicket__PlatformPaymentFailed();
    error EventTicket__SupplyCannotBeZero();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    struct TicketInfo {
        string eventName;
        string seatNumber;
        bool isVIP;
        uint256 mintedAt;
    }

    uint256 public maxSupply;
    uint256 public mintPrice;
    address public eventOrganizer;
    address public platformAddress;
    uint256 public nextTicketId = 0;

    mapping(address user => uint256) lastMintTime;
    mapping(uint256 tokenId => TicketInfo) tickets;

    uint256 public constant MINT_COOLDOWN = 5 seconds;
    uint256 public immutable I_ORGANIZER_PERCENTAGE; // 95% to organizer
    uint256 public immutable I_ROYALTY_FEE_PERCENTAGE; // royalty fee on secondary Markets
    address public immutable I_USER_VERFIER_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TicketMinted(address indexed user, uint256 indexed ticketId, string seatNumber, bool isVIP);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyVerified() {
        if (!UserVerification(I_USER_VERFIER_ADDRESS).isVerified(msg.sender)) {
            revert EventTicket__UserNotVerified();
        }
        _;
    }

    modifier mintCooldown() {
        if (block.timestamp < lastMintTime[msg.sender] + MINT_COOLDOWN) {
            revert EventTicket__mintCooldown(msg.sender, block.timestamp);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        address _eventOrganizer,
        address _platformAddress,
        uint256 _organizerPercentage,
        address _userVerfierAddress,
        uint256 _royaltyFeePercentage
    ) ERC721(name, symbol) Ownable(msg.sender) {
        if(_maxSupply == 0 ) {
            revert EventTicket__SupplyCannotBeZero();
        }
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        if (_organizerPercentage > 9800 && _royaltyFeePercentage > 1000) {
            revert EventTicket__InvalidOrganizerPercentage(_organizerPercentage);
        }
        if (_eventOrganizer == address(0) && _platformAddress == address(0) && _userVerfierAddress == address(0)) {
            revert EventTicket__ZeroAddressNotAllowed();
        }
        eventOrganizer = _eventOrganizer;
        platformAddress = _platformAddress;
        I_ORGANIZER_PERCENTAGE = _organizerPercentage;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
        I_ROYALTY_FEE_PERCENTAGE = _royaltyFeePercentage;
    }

    function mintTicket(string memory _eventName, string memory _seatNumber, bool _isVIP, string memory tokenURI)
        external
        payable
        onlyVerified
        mintCooldown
        nonReentrant
    {
        require(nextTicketId < maxSupply, "Max supply reached");
        require(msg.value >= mintPrice, "Insufficient payment");

        uint256 ticketId = nextTicketId++;

        tickets[ticketId] =
            TicketInfo({eventName: _eventName, seatNumber: _seatNumber, isVIP: _isVIP, mintedAt: block.timestamp});

        _safeMint(msg.sender, ticketId);
        _setTokenURI(ticketId, tokenURI);
        lastMintTime[msg.sender] = block.timestamp;

        // Distribute funds
        uint256 organizerShare = (msg.value * I_ORGANIZER_PERCENTAGE) / 10000;
        uint256 platformShare = msg.value - organizerShare;

        (bool sent1,) = payable(eventOrganizer).call{value: organizerShare}("");
        if (!sent1) {
            revert EventTicket__OrganizerPaymentFailed();
        }

        (bool sent2,) = payable(platformAddress).call{value: platformShare}("");
        if (!sent2) {
            revert EventTicket__PlatformPaymentFailed();
        }

        emit TicketMinted(msg.sender, ticketId, _seatNumber, _isVIP);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {   
        _requireOwned(tokenId);
        receiver = eventOrganizer;
        royaltyAmount = (salePrice * I_ROYALTY_FEE_PERCENTAGE) / 10000;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
