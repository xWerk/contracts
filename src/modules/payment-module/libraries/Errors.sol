// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {PaymentModule} contract may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    PAYMENT-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Thrown when the caller is a contract that does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Thrown when the end time of a payment request is in the past
    error EndTimeInThePast();

    /// @notice Thrown when the start time is later than the end time
    error StartTimeGreaterThanEndTime();

    /// @notice Thrown when the payment amount set for a new paymentRequest is zero
    error ZeroPaymentAmount();

    /// @notice Thrown when the payment amount is less than the payment request value
    error PaymentAmountLessThanRequestedAmount(uint256 amount);

    /// @notice Thrown when a payment in the native token (ETH) fails
    error NativeTokenPaymentFailed();

    /// @notice Thrown when a linear or tranched stream is created with the native token as the payment asset
    error OnlyERC20StreamsAllowed();

    /// @notice Thrown when a payer attempts to pay a canceled payment request
    error RequestCanceled();

    /// @notice Thrown when a payer attempts to pay a completed payment request
    error RequestPaid();

    /// @notice Thrown when `msg.sender` is not the payment request recipient
    error OnlyRequestRecipient();

    /// @notice Thrown when the recipient address is the zero address
    error InvalidZeroAddressRecipient();

    /// @notice Thrown when the payment interval (endTime - startTime) is too short for the selected recurrence
    /// i.e. recurrence is set to weekly but interval is shorter than 1 week
    error PaymentIntervalTooShortForSelectedRecurrence();

    /// @notice Thrown when a tranched stream has a one-off recurrence type
    error TranchedStreamInvalidOneOffRecurence();

    /// @notice Thrown when the caller is not the initial stream sender
    error OnlyInitialStreamSender(address initialSender);

    /// @notice Thrown when the payment request is null
    error NullRequest();

    /// @notice Thrown when the payment request has an unlimited recurrence type but the payment method is not transfer-based
    error OnlyTransferAllowedForCustomRecurrence();

    /// @notice Thrown when the payment request has an unlimited recurrence type and the current block timestamp is greater than the payment request end time
    error RequestExpired();
}
