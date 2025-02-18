// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the {PaymentModule} related contracts
library Types {
    /// @notice Enum representing the different recurrences a payment can have
    /// @custom:value OneOff One single payment that must be made either as a single transfer or through a linear stream
    /// @custom:value Weekly Multiple weekly payments that must be made either by transfer or a tranched stream
    /// @custom:value Monthly Multiple weekly payments that must be made either by transfer or tranched stream
    /// @custom:value Yearly Multiple weekly payments that must be made either by transfer or tranched stream
    enum Recurrence {
        OneOff,
        Weekly,
        Monthly,
        Yearly
    }

    /// @notice Enum representing the different payment methods
    /// @custom:value Transfer Payment method must be made through a transfer
    /// @custom:value LinearStream Payment method must be made through a linear stream
    /// @custom:value TranchedStream Payment method must be made through a tranched stream
    enum Method {
        Transfer,
        LinearStream,
        TranchedStream
    }

    /// @notice Struct encapsulating the different values describing a payment config
    /// @param method The payment method
    /// @param recurrence The payment recurrence
    /// @param paymentsLeft The number of payments required to fully settle the payment request (only for transfer or tranched stream based payment requests)
    /// @param asset The address of the payment asset
    /// @param amount The amount that must be paid
    /// @param streamId The ID of the linear or tranched stream if payment method is either `LinearStream` or `TranchedStream`, otherwise 0
    struct Config {
        // slot 0
        Method method;
        Recurrence recurrence;
        uint40 paymentsLeft;
        address asset;
        // slot 1
        uint128 amount;
        // slot 2
        uint256 streamId;
    }

    /// @notice Enum representing the different statuses a payment request can have
    /// @custom:value Pending Payment request waiting to be accepted by the payer
    /// @custom:value Accepted Payment request has been accepted and is being paid; if the payment method is a One-Off Transfer,
    /// the payment request status will automatically be set to `Paid`. Otherwise, it will remain `Accepted` until it is fully paid
    /// @custom:value Paid Payment request has been fully paid
    /// @custom:value Canceled Payment request canceled by declined by the recipient (if Transfer-based) or stream sender
    enum Status {
        Pending,
        Accepted,
        Paid,
        Canceled
    }

    /// @notice Struct encapsulating the different values describing a payment request
    /// @param status The status of the payment request
    /// @param startTime The unix timestamp indicating when the payment starts
    /// @param endTime The unix timestamp indicating when the payment ends
    /// @param recipient The address to which the payment is made
    /// @param payment The payment configurations
    struct PaymentRequest {
        // slot 0
        bool wasCanceled;
        bool wasAccepted;
        uint40 startTime;
        uint40 endTime;
        address recipient;
        // slot 1, 2 and 3
        Config config;
    }
}
