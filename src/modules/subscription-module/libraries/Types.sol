// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the {SubscriptionModule} related contracts
library Types {
    /// @notice Struct encapsulating the subscription consent terms recorded on-chain by a {Space}
    /// @dev This struct is hashed (via `keccak256(abi.encode(subscription))`) to derive the `subscriptionId`.
    /// Backend MUST abi-encode these exact fields in this exact order, and the layout MUST be
    /// treated as frozen since any change to the field set alters every derived `subscriptionId`.
    /// @param amount The amount pulled from the {Space} per billing cycle
    /// @param interval The number of seconds between two consecutive billing cycles (e.g. 30 days)
    /// @param start The earliest timestamp when the first cycle becomes chargeable
    /// @param periods The total number of cycles, capping the total exposure at `amount * periods`
    /// @param tier The subscription plan identifier
    /// @param space The payer {Space} smart account (resolves off-chain to the entity that gets premium features)
    /// @param asset The address of the ERC-20 asset used to pay (e.g. USDC)
    /// @param nonce A disambiguator so identical-terms re-subscribes derive a distinct `subscriptionId`
    struct Subscription {
        uint128 amount;
        uint40 interval;
        uint40 start;
        uint16 periods;
        uint8 tier;
        address space;
        address asset;
        uint256 nonce;
    }

    /// @notice Enum representing the lifecycle state of a subscription, keyed by its `subscriptionId`
    /// @dev `NotSubscribed` is intentionally the first member so it is the default (`0`) value for any
    /// never-subscribed `subscriptionId`
    /// @custom:value NotSubscribed The `subscriptionId` has never been subscribed (default)
    /// @custom:value Subscribed The subscription is active and chargeable
    /// @custom:value Canceled The subscription has been cancelled; charging is permanently disabled
    enum Status {
        NotSubscribed,
        Subscribed,
        Canceled
    }
}
