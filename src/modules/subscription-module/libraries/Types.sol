// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the {SubscriptionModule} related contracts
library Types {
    /// @notice Enum representing the derived, time-dependent lifecycle state of a subscription
    /// @dev This value is never stored. It is computed on demand by {SubscriptionModule.statusOf} from the
    /// stored fields (`space`, `isRevoked`, `start`, `interval`, `cycles`, `cyclesCharged`) and
    /// `block.timestamp`, following the same dynamic-status pattern as Sablier's `statusOf`
    /// @custom:value Null The `subscriptionId` has never been registered (default)
    /// @custom:value Active The subscription is registered and paid up to (or within) the current cycle
    /// @custom:value PastDue At least one elapsed cycle has not been charged yet (a payment is overdue)
    /// @custom:value Revoked The subscription has been revoked; charging is permanently disabled
    /// @custom:value Expired All `cycles` have been charged; the subscription reached its natural end
    enum Status {
        Null,
        Active,
        PastDue,
        Revoked,
        Expired
    }

    /// @notice Struct encapsulating the backend-signed inputs a {Space} consents to at subscribe time
    /// @dev The backend signs over `keccak256(abi.encode(subscriptionId, space, asset, interval,
    /// cycles, validUntil, block.chainid))`. The signed layout must be treated as frozen.
    /// @param subscriptionId The backend-generated unique identifier; also the mapping key and the replay guard
    /// @param space The payer {Space} smart account; must be `msg.sender` at subscribe
    /// @param interval The number of seconds between two consecutive cycles (e.g. 30 days); backend-supplied & signed
    /// @param cycles The total number of cycles the subscription runs for
    /// @param validUntil The timestamp after which the signed terms can no longer be used to subscribe (quote expiry)
    /// @param asset The address of the ERC-20 asset used to pay each cycle (e.g. USDC); backend-supplied & signed
    struct SubscribeInput {
        // slot 0
        bytes32 subscriptionId;
        // slot 1
        address space;
        uint40 interval;
        uint16 cycles;
        uint40 validUntil;
        // slot 2
        address asset;
    }

    /// @notice Struct encapsulating the full subscription details pinned on-chain at subscribe time
    /// @dev These values are copied from a backend-signed {SubscribeInput} once the signature is verified.
    /// Note: no price is stored on-chain. {SubscriptionModule.charge} pulls a relayer-supplied `amount` of the
    /// stored `asset`, so the price is free to change between cycles without touching this struct, while the
    /// charged token stays fixed for the life of the subscription.
    /// @param space The payer {Space} smart account that consented to the subscription
    /// @param interval The number of seconds between two consecutive cycles
    /// @param cycles The total number of cycles
    /// @param start The timestamp at which cycle 0 became chargeable (set to `block.timestamp` at subscribe)
    /// @param asset The ERC-20 asset pulled from the {Space} each cycle (pinned at subscribe time)
    /// @param isRevoked Whether the {Space} has revoked the subscription; charging is then permanently disabled
    /// @param cyclesCharged The number of cycles charged so far; when it reaches `cycles` the subscription is
    /// {Status.Expired}
    struct Subscription {
        // slot 0
        address space;
        uint40 interval;
        uint16 cycles;
        uint40 start;
        // slot 1
        address asset;
        bool isRevoked;
        uint16 cyclesCharged;
    }
}
