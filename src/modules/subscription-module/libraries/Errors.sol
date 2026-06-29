// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {SubscriptionModule} contract may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    SUBSCRIPTION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a {Space} subscribes while it already holds an active subscription
    error SubscriptionAlreadyActive();

    /// @notice Thrown when subscribing to a tier that has no pricing configuration set
    error InvalidTier();

    /// @notice Thrown when configuring a tier with a zero `amount`
    error InvalidTierAmount();

    /// @notice Thrown when configuring a tier with a zero `interval`
    error InvalidTierInterval();

    /// @notice Thrown when subscribing with a `periods` value outside the supported `[1, 256]` range
    error InvalidPeriods();

    /// @notice Thrown when charging or canceling a {Space} that has no subscription
    error SubscriptionNotFound();

    /// @notice Thrown when charging or canceling a subscription that has been canceled
    error SubscriptionCanceled();

    /// @notice Thrown when a subscription was already charged for this `cycle`
    error CycleAlreadyCharged();

    /// @notice Thrown when charging a `cycle` before its due time (`start + cycle * interval`)
    error CycleNotDue();

    /// @notice Thrown when charging a `cycle` greater than or equal to the total number of `periods`
    error CycleOutOfBounds();

    /// @notice Thrown when the treasury address is set to the zero address
    error InvalidZeroAddressTreasury();

    /// @notice Thrown when allowlisting the zero address as an asset
    error InvalidZeroAddressAsset();

    /// @notice Thrown when subscribing with an asset that is not on the allowlist
    error AssetNotAllowed();
}
