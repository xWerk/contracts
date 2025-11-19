// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IOwnable } from "../interfaces/IOwnable.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title Ownable
/// @notice See the documentation in {IOwnable}
abstract contract Ownable is IOwnable {
    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOwnable
    address public override owner;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the address of the contract owner
    constructor(address _owner) {
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Reverts if the `msg.sender` is not the contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert Errors.Unauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOwnable
    function transferOwnership(address newOwner) public onlyOwner {
        // Checks: the new owner is not the zero address
        if (newOwner == address(0)) {
            revert Errors.InvalidOwnerZeroAddress();
        }

        // Effects: update the address of the current owner
        owner = newOwner;

        // Log the ownership update
        emit OwnershipTransferred({ oldOwner: msg.sender, newOwner: newOwner });
    }
}
