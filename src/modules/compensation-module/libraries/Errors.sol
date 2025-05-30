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

    /// @notice Thrown when the caller is not the compensation component sender
    error OnlyComponentSender();

    /// @notice Thrown when the caller is not the compensation component recipient
    error OnlyComponentRecipient();

    /// @notice Thrown when the compensation component rate per second is zero
    error InvalidZeroRatePerSecond();

    /// @notice Thrown when the compensation component asset is the zero address
    error InvalidZeroAddressAsset();

    /// @notice Thrown when the compensation component does not exist
    error InvalidComponentId();

    /// @notice Thrown when the deposit amount is zero
    error InvalidZeroDepositAmount();

    /// @notice Thrown when the compensation component does not exist
    error ComponentNull();

    /// @notice Thrown when the caller is not the initial stream sender
    error OnlyInitialStreamSender(address initialSender);

    /// @notice Thrown when the foo value is invalid
    error InvalidFooValue();
}
