// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {SubscriptionModule} contract may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    SUBSCRIPTION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is not the {Space} declared in the subscription terms
    error OnlySubscriptionSpace();

    /// @notice Thrown when subscribing with a `subscriptionId` that already exists
    error SubscriptionAlreadyExists();

    /// @notice Thrown when charging a `subscriptionId` that does not exist
    error SubscriptionNotFound();

    /// @notice Thrown when a subscription was already charged for this `cycle`
    error CycleAlreadyCharged();

    /// @notice Thrown when charging a `cycle` before its due time (`start + cycle * interval`)
    error CycleNotDue();

    /// @notice Thrown when charging a `cycle` greater than or equal to the total number of `periods`
    error CycleOutOfBounds();

    /// @notice Thrown when charging a subscription that has been canceled
    error SubscriptionCanceled();

    /// @notice Thrown when the treasury address is set to the zero address
    error InvalidZeroAddressTreasury();
}
