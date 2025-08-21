// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./EventTicket.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EventFactory is Ownable {
    
    address public platformAddress;
    address public immutable i_userVerfierAddress;
    EventTicket[] public deployedEvents;
    
    mapping(address => EventTicket[]) public organizerEvents;
    
    event EventCreated(
        address indexed organizer,
        address indexed eventContract,
        string name,
        uint256 maxSupply,
        uint256 mintPrice
    );
    
    constructor(address _platformAddress, address _userVerfierAddress) Ownable(msg.sender){
        platformAddress = _platformAddress;
        i_userVerfierAddress = _userVerfierAddress;
    }
    
    function createEvent(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 mintPrice,
        uint256 organizerPercentage,
        uint256 royaltyFeePercentage
    ) external returns (EventTicket) {
        EventTicket newEvent = new EventTicket(
            name,
            symbol,
            maxSupply,
            mintPrice,
            msg.sender, // organizer
            platformAddress,
            organizerPercentage,
            i_userVerfierAddress,
            royaltyFeePercentage
        );
        
        deployedEvents.push(newEvent);
        organizerEvents[msg.sender].push(newEvent);
        
        emit EventCreated(msg.sender, address(newEvent), name, maxSupply, mintPrice);
        
        return newEvent;
    }
    
    function getDeployedEvents() external view returns (EventTicket[] memory) {
        return deployedEvents;
    }
    
    function getOrganizerEvents(address organizer) external view returns (EventTicket[] memory) {
        return organizerEvents[organizer];
    }
}
