// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the {SubscriptionModule} related contracts
library Types {
    /// @notice Enum representing the derived, time-dependent lifecycle state of a subscription
    /// @dev This value is never stored. It is computed on demand by {SubscriptionModule.statusOf} from the
    /// stored fields (`space`, `isRevoked`, `start`, `interval`, `periods`, `chargedCount`) and
    /// `block.timestamp`, following the same dynamic-status pattern as Sablier's `statusOf`
    /// @custom:value NotRegistered The `subscriptionId` has never been registered (default)
    /// @custom:value Active The subscription is registered and paid up to (or within) the current cycle
    /// @custom:value PastDue At least one elapsed cycle has not been charged yet (a payment is overdue)
    /// @custom:value Revoked The subscription has been revoked; charging is permanently disabled
    /// @custom:value Expired All `periods` cycles have been charged; the subscription reached its natural end
    enum Status {
        NotRegistered,
        Active,
        PastDue,
        Revoked,
        Expired
    }

    /// @notice Struct encapsulating the backend-signed inputs a {Space} consents to at subscribe time
    /// @dev The backend signs over `keccak256(abi.encode(subscriptionId, space, tier, asset, amount, interval,
    /// periods, block.chainid))`. The signed layout must be treated as frozen.
    /// @param subscriptionId The backend-generated unique identifier; also the mapping key and the replay guard
    /// @param space The payer {Space} smart account; must be `msg.sender` at subscribe
    /// @param interval The number of seconds between two consecutive cycles (e.g. 30 days); backend-supplied & signed
    /// @param periods The total number of cycles, capping the total exposure at `amount * periods`
    /// @param asset The address of the ERC-20 asset used to pay each cycle (e.g. USDC); backend-supplied & signed
    /// @param tier The subscription plan identifier (informational only; emitted in events, not priced on-chain)
    /// @param amount The per-cycle price pulled from the {Space}; backend-supplied & signed (THE protected value)
    struct SubscribeInput {
        // slot 0
        bytes32 subscriptionId;
        // slot 1
        address space;
        uint40 interval;
        uint16 periods;
        // slot 2
        address asset;
        uint8 tier;
        // slot 3
        uint128 amount;
    }

    /// @notice Struct encapsulating the full subscription details pinned on-chain at subscribe time
    /// @dev These values are copied from a backend-signed {SubscribeInput} once the signature is verified.
    /// {SubscriptionModule.charge} reads `amount` from here for the life of the subscription,
    /// so a later backend price change cannot affect an existing subscription
    /// @param space The payer {Space} smart account that consented to the subscription
    /// @param interval The number of seconds between two consecutive cycles
    /// @param periods The total number of cycles
    /// @param start The timestamp at which cycle 0 became chargeable (set to `block.timestamp` at subscribe)
    /// @param asset The ERC-20 asset pulled from the {Space} each cycle
    /// @param tier The subscription plan identifier (informational)
    /// @param isRevoked Whether the {Space} has revoked the subscription; charging is then permanently disabled
    /// @param chargedCount The number of cycles charged so far; when it reaches `periods` the subscription is
    /// {Status.Expired}
    /// @param amount The fixed per-cycle charge pinned at subscribe time
    struct Subscription {
        // slot 0
        address space;
        uint40 interval;
        uint16 periods;
        uint40 start;
        // slot 1
        address asset;
        uint8 tier;
        bool isRevoked;
        uint16 chargedCount;
        // slot 2
        uint128 amount;
    }
}
