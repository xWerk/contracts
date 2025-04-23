// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {CompensationModule} contract may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    COMPENSATION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Thrown when the recipient address is the zero address
    error InvalidZeroAddressRecipient();

    /// @notice Thrown when the caller is a contract that does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Thrown when the components array is empty
    error InvalidEmptyComponentsArray();

    /// @notice Thrown when the recipients array is empty
    error InvalidEmptyRecipientsArray();

    /// @notice Thrown when the recipients and components arrays have different lengths
    error InvalidRecipientsAndComponentsArraysLength();
}
