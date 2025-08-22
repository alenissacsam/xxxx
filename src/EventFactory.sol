// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {EventTicket} from "./EventTicket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EventFactory
 * @author alenissacsam
 * @dev A factory contract for creating and managing custom event ticket contracts.
 */
contract EventFactory is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable I_PLATFORM_ADDRESS;
    address public immutable I_USER_VERFIER_ADDRESS;
    EventTicket[] public deployedEvents;

    mapping(address => EventTicket[]) public organizerEvents;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event EventCreated(
        address indexed organizer, address indexed eventContract, string name, uint256 maxSupply, uint256 mintPrice
    );

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address _platformAddress, address _userVerfierAddress) Ownable(msg.sender) {
        I_PLATFORM_ADDRESS = _platformAddress;
        I_USER_VERFIER_ADDRESS = _userVerfierAddress;
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
            I_PLATFORM_ADDRESS,
            organizerPercentage,
            I_USER_VERFIER_ADDRESS,
            royaltyFeePercentage
        );

        deployedEvents.push(newEvent);
        organizerEvents[msg.sender].push(newEvent);

        emit EventCreated(msg.sender, address(newEvent), name, maxSupply, mintPrice);

        return newEvent;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getDeployedEvents() external view returns (EventTicket[] memory) {
        return deployedEvents;
    }

    function getOrganizerEvents(address organizer) external view returns (EventTicket[] memory) {
        return organizerEvents[organizer];
    }
}
