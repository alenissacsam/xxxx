// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UserVerification
 * @author alenissacsam
 * @dev A smart contract for managing user verification on the blockchain.
 * It allows the owner to verify users, revoke verification, and manage user metadata.
 * This contract is designed to be used with other contracts that require user verification.
 */
contract UserVerification is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UserVerification__UserAlreadyVerified(address user);
    error UserVerification__UserNotVerified(address user);
    error UserVerification__OffsetOutOfBounds();
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) public verifiedUsers;
    mapping(address => uint256) public verificationTime;
    mapping(address => string) public userMetadata; // Optional: store verification details

    address[] public verifiedUsersList;

    event UserVerified(address indexed user, uint256 timestamp);
    event UserRevoked(address indexed user, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    function verifyUser(address user) external onlyOwner {
        if (verifiedUsers[user]) {
            revert UserVerification__UserAlreadyVerified(user);
        }

        verifiedUsers[user] = true;
        verificationTime[user] = block.timestamp;
        verifiedUsersList.push(user);

        emit UserVerified(user, block.timestamp);
    }

    function verifyUserWithMetadata(address user, string memory metadata) external onlyOwner {
        if (verifiedUsers[user]) {
            revert UserVerification__UserAlreadyVerified(user);
        }

        verifiedUsers[user] = true;
        verificationTime[user] = block.timestamp;
        userMetadata[user] = metadata;
        verifiedUsersList.push(user);

        emit UserVerified(user, block.timestamp);
    }

    function revokeUser(address user) external onlyOwner {
        if (!verifiedUsers[user]) {
            revert UserVerification__UserNotVerified(user);
        }
        verifiedUsers[user] = false;
        emit UserRevoked(user, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isVerified(address user) external view returns (bool) {
        return verifiedUsers[user];
    }

    function getVerifiedUsersCount() external view returns (uint256) {
        return verifiedUsersList.length;
    }

    function getVerifiedUsers(uint256 offset, uint256 limit) external view returns (address[] memory) {
        if (offset >= verifiedUsersList.length) {
            revert UserVerification__OffsetOutOfBounds();
        }

        uint256 end = offset + limit;
        if (end > verifiedUsersList.length) {
            end = verifiedUsersList.length;
        }

        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = verifiedUsersList[i];
        }

        return result;
    }
}
