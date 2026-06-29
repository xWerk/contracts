// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title ISubscriptionModule
/// @notice Contract module that provides on-chain recurring subscription billing using a
/// "subscribe-by-Space" consent model: a {Space} records its consent on-chain by calling
/// {subscribe} (admin-gated through `Space.execute`), and a permissionless relayer subsequently
/// pulls each due cycle's fixed charge to a hardcoded treasury via {charge}.
///
/// @dev Pricing is protocol-owned: the owner configures each `tier` with a per-cycle `amount` and
/// `interval` via {setTier}, and maintains an allowlist of accepted ERC-20 assets (e.g. USDC) via
/// {setAssetAllowed}. A {Space} subscribes by picking a `tier` and an allowed `asset` (plus `periods`
/// and `start`); the price and cadence are snapshotted from the tier config and the asset is recorded
/// on the subscription, so a {Space} cannot choose its own price or cadence, later tier-config changes
/// do not re-price existing subscriptions, and disallowing an asset does not affect subscriptions that
/// already snapshotted it.
///
/// A {Space} holds at most ONE active subscription at a time, keyed by the {Space} address.
/// (Re)subscribing overwrites the terms and resets the charge history, so a {Space} that has canceled
/// (or whose subscription ran its course) can simply subscribe again with a clean slate.
///
/// The {Space} must grant this module an ERC-20 allowance over `asset` before any cycle can be
/// charged: each {charge} pulls `amount` via `safeTransferFrom`, so the {Space} is expected to approve
/// the module for the full exposure (`amount * periods`) at subscribe time. A {charge} reverts if the
/// remaining allowance (or balance) is insufficient for that cycle.
interface ISubscriptionModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the owner configures (or updates) a tier's pricing
    /// @param tier The plan identifier
    /// @param amount The per-cycle amount charged for the tier
    /// @param interval The number of seconds between two consecutive cycles
    event TierConfigured(uint8 indexed tier, uint128 amount, uint40 interval);

    /// @notice Emitted when the owner removes a tier's pricing configuration
    /// @param tier The plan identifier
    event TierRemoved(uint8 indexed tier);

    /// @notice Emitted when the owner allows or disallows an ERC-20 asset
    /// @param asset The ERC-20 asset
    /// @param allowed Whether the asset is now allowed for new subscriptions
    event AssetAllowed(address indexed asset, bool allowed);

    /// @notice Emitted when a {Space} subscribes
    /// @param space The payer {Space} smart account
    /// @param tier The plan identifier
    /// @param asset The ERC-20 asset the subscription is billed in
    /// @param amount The per-cycle amount snapshotted from the tier config
    /// @param interval The seconds between cycles snapshotted from the tier config
    /// @param periods The total number of cycles
    /// @param start The earliest timestamp at which cycle 0 becomes chargeable
    event Subscribed(
        address indexed space,
        uint8 indexed tier,
        address asset,
        uint128 amount,
        uint40 interval,
        uint16 periods,
        uint40 start
    );

    /// @notice Emitted when a cycle is successfully charged
    /// @dev Carries enough data to key a DB row (`space`, `cycle`) for off-chain indexing
    /// @param space The payer {Space} smart account that was charged
    /// @param cycle The zero-based index of the charged cycle
    /// @param amount The amount pulled from the {Space} to the treasury
    /// @param paidUntil The timestamp until which the subscription is paid (`start + (cycle + 1) * interval`)
    event SubscriptionCharged(address indexed space, uint256 indexed cycle, uint128 amount, uint40 paidUntil);

    /// @notice Emitted when a {Space} cancels its subscription
    /// @param space The payer {Space} smart account
    event SubscriptionCanceled(address indexed space);

    /// @notice Emitted when the owner updates the treasury address
    /// @param oldTreasury The previous treasury address
    /// @param newTreasury The new treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the treasury address that receives all subscription charges
    function treasury() external view returns (address);

    /// @notice Returns whether an ERC-20 `asset` is allowed for new subscriptions
    /// @param asset The ERC-20 asset
    function isAssetAllowed(address asset) external view returns (bool);

    /// @notice Retrieves the pricing configuration of the `tier`
    /// @param tier The plan identifier
    /// @return config The tier pricing configuration (a zero `amount` means the tier is not configured)
    function getTierConfig(uint8 tier) external view returns (Types.TierConfig memory config);

    /// @notice Returns whether the `cycle` of the `space` subscription has already been charged
    /// @param space The payer {Space} smart account
    /// @param cycle The zero-based index of the cycle
    function isCharged(address space, uint256 cycle) external view returns (bool);

    /// @notice Retrieves the `space` subscription (terms + lifecycle status)
    /// @dev A never-subscribed {Space} returns a zero struct whose `status` is `NotSubscribed`
    /// @param space The payer {Space} smart account
    /// @return subscription The stored subscription (its `status` field carries the lifecycle state)
    function getSubscription(address space) external view returns (Types.Subscription memory subscription);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Configures (or updates) the pricing of a `tier`
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    /// - `amount` and `interval` must be non-zero
    ///
    /// Notes:
    /// - updating a tier does NOT re-price existing subscriptions; the values are snapshotted at subscribe time
    ///
    /// @param tier The plan identifier
    /// @param amount The per-cycle amount to charge for the tier
    /// @param interval The number of seconds between two consecutive cycles
    function setTier(uint8 tier, uint128 amount, uint40 interval) external;

    /// @notice Removes a `tier`'s pricing configuration, preventing new subscriptions to it
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// Notes:
    /// - existing subscriptions to the tier are unaffected (their terms are already snapshotted)
    ///
    /// @param tier The plan identifier
    function removeTier(uint8 tier) external;

    /// @notice Records the calling {Space}'s consent to a recurring subscription on-chain
    ///
    /// Requirements:
    /// - the calling {Space} must not already hold an active subscription
    /// - the `tier` must be configured (see {setTier})
    /// - the `asset` must be allowed (see {setAssetAllowed})
    /// - `periods` must be in the range `[1, 256]`
    ///
    /// Notes:
    /// - the paying {Space} is `msg.sender`; consent is proven by `Space.execute`'s `onlyAdminOrEntrypoint` gate
    /// - the per-cycle `amount` and `interval` are snapshotted from the tier config
    /// - the {Space} is expected to approve this module for `amount * periods` of the `asset` at subscribe time
    /// - re-subscribing after a cancel overwrites the terms and resets the charge history
    ///
    /// @param tier The plan identifier to subscribe to
    /// @param asset The allowed ERC-20 asset to be billed in
    /// @param periods The total number of cycles
    /// @param start The earliest timestamp at which cycle 0 becomes chargeable
    function subscribe(uint8 tier, address asset, uint16 periods, uint40 start) external;

    /// @notice Pulls one cycle's fixed charge from the `space` to the treasury
    ///
    /// Requirements:
    /// - the `space` must hold an active (non-canceled) subscription
    /// - the `cycle` must not have been charged before for the current subscription
    /// - the `cycle` must be due (`block.timestamp >= start + cycle * interval`)
    /// - the `cycle` must be within bounds (`cycle < periods`)
    /// - the `space` must have approved this module for at least `amount` of the asset
    ///
    /// Notes:
    /// - permissionless: any caller can trigger an already-consented charge, but funds always go to the
    /// treasury and the amount is pinned in the stored terms, so it cannot be abused
    ///
    /// @param space The payer {Space} smart account to charge
    /// @param cycle The zero-based index of the cycle to charge
    function charge(address space, uint256 cycle) external;

    /// @notice Cancels the calling {Space}'s subscription, preventing any further charges
    ///
    /// Requirements:
    /// - the calling {Space} must hold an active subscription
    ///
    /// Notes:
    /// - the paying {Space} is `msg.sender`; only the {Space} itself can cancel its subscription
    function cancel() external;

    /// @notice Updates the treasury address that receives all subscription charges
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newTreasury The new treasury address
    function setTreasury(address newTreasury) external;

    /// @notice Allows or disallows an ERC-20 asset for new subscriptions
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    /// - `asset` must not be the zero address
    ///
    /// Notes:
    /// - only affects NEW subscriptions; existing ones keep charging in the asset they snapshotted
    ///
    /// @param asset The ERC-20 asset to allow or disallow
    /// @param allowed Whether the asset should be allowed
    function setAssetAllowed(address asset, bool allowed) external;
}
