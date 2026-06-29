// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the {SubscriptionModule} related contracts
library Types {
    /// @notice Enum representing the lifecycle state of a {Space}'s subscription
    /// @dev `NotSubscribed` is intentionally the first member so it is the default (`0`) value for any
    /// {Space} that has never subscribed (a zero {Subscription} has `status == NotSubscribed`)
    /// @custom:value NotSubscribed The {Space} has no subscription (default)
    /// @custom:value Subscribed The subscription is active and chargeable
    /// @custom:value Canceled The subscription has been cancelled; the {Space} may subscribe again
    enum Status {
        NotSubscribed,
        Subscribed,
        Canceled
    }

    /// @notice Owner-managed pricing configuration for a subscription tier
    /// @dev The {SubscriptionModule} owner sets these; a tier is considered configured iff `amount != 0`.
    /// The values are snapshotted into a {Subscription} at subscribe time, so later config changes do
    /// not re-price existing subscriptions.
    /// @param amount The amount pulled from the {Space} per billing cycle
    /// @param interval The number of seconds between two consecutive billing cycles (e.g. 30 days)
    struct TierConfig {
        uint128 amount;
        uint40 interval;
    }

    /// @notice Struct encapsulating a {Space}'s subscription (terms + lifecycle status)
    /// @dev The caller of {ISubscriptionModule-subscribe} supplies only `tier`, `asset`, `periods` and
    /// `start`; `amount` and `interval` are snapshotted from the tier's {TierConfig} and `asset` is
    /// recorded from the caller's allowlisted choice, so a caller cannot set its own price or cadence.
    /// The paying {Space} is the `msg.sender` of `subscribe`, so it is not stored here. A {Space} holds
    /// at most one active subscription at a time; (re)subscribing overwrites the terms and resets the
    /// charge history.
    /// @param amount The amount pulled from the {Space} per billing cycle (snapshotted from {TierConfig})
    /// @param interval The seconds between two consecutive billing cycles (snapshotted from {TierConfig})
    /// @param start The earliest timestamp when the first cycle becomes chargeable
    /// @param periods The total number of cycles, capping the total exposure at `amount * periods`.
    /// Must be in `[1, 256]` since the charge history is tracked as a 256-bit bitmap.
    /// @param tier The subscription plan identifier
    /// @param status The lifecycle state of the subscription
    /// @param asset The ERC-20 token charged each cycle (the caller's allowlisted choice)
    struct Subscription {
        uint128 amount;
        uint40 interval;
        uint40 start;
        uint16 periods;
        uint8 tier;
        Status status;
        address asset;
    }
}
