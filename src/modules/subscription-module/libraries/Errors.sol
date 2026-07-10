// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {SubscriptionModule} contract may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    SUBSCRIPTION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is not the {Space} declared in the subscription inputs (on {subscribe} or {revoke})
    error OnlySubscriptionSpace();

    /// @notice Thrown when the caller of {charge} or {chargeBatch} is not the trusted relayer
    error OnlyRelayer();

    /// @notice Thrown when {chargeBatch} is called with `subscriptionIds` and `amounts` of different lengths
    error ArrayLengthMismatch();

    /// @notice Thrown when the backend signature does not recover to the stored relayer (tampered terms or wrong signer)
    error InvalidRelayerSignature();

    /// @notice Thrown when subscribing with signed terms past their `validUntil` expiry (stale quote)
    error SignatureExpired();

    /// @notice Thrown when subscribing with a `subscriptionId` that already exists
    error SubscriptionAlreadyExists();

    /// @notice Thrown when charging or revoking a `subscriptionId` that has never been registered
    error SubscriptionNull();

    /// @notice Thrown when charging the next cycle before its due time (`start + cyclesCharged * interval`);
    /// also the double-charge guard, since each successful charge pushes the next due time one interval ahead
    error CycleNotDue();

    /// @notice Thrown when charging a subscription whose cycles have all been charged (natural end)
    error SubscriptionEnded();

    /// @notice Thrown when charging or revoking a subscription that has been revoked
    error SubscriptionRevoked();

    /// @notice Thrown when the relayer address is set to the zero address
    error InvalidZeroAddressRelayer();

    /// @notice Thrown when the treasury address is set to the zero address
    error InvalidZeroAddressTreasury();
}
