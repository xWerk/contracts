// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title ISubscriptionModule
/// @notice Contract module that provides on-chain recurring subscription billing using a
/// "subscribe-by-Space" consent model: a {Space} records its consent on-chain by calling
/// {subscribe} (admin-gated through `Space.execute`), and a permissionless relayer subsequently
/// pulls each due cycle's amount to a hardcoded treasury via {charge}
/// @dev The {Space} must grant this module an ERC-20 allowance over `asset` before any cycle can be
/// charged: each {charge} pulls `amount` via `safeTransferFrom`, so the {Space} is expected to approve
/// the module for the full exposure (`amount * periods`) at subscribe time. A {charge} reverts if the
/// remaining allowance (or balance) is insufficient for that cycle.
interface ISubscriptionModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a {Space} subscribes
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The unique identifier of the subscription, derived as `keccak256(abi.encode(subscription))`
    /// @param tier The plan identifier
    /// @param asset The ERC-20 asset used to pay each cycle
    /// @param amount The fixed charge pulled per cycle
    /// @param interval The number of seconds between two consecutive cycles
    /// @param periods The total number of cycles
    /// @param start The earliest timestamp at which cycle 0 becomes chargeable
    event Subscribed(
        address indexed space,
        bytes32 indexed subscriptionId,
        uint8 tier,
        address asset,
        uint128 amount,
        uint40 interval,
        uint16 periods,
        uint40 start
    );

    /// @notice Emitted when a cycle is successfully charged
    /// @param space The payer {Space} smart account that was charged
    /// @param subscriptionId The unique identifier of the subscription
    /// @param cycle The zero-based index of the charged cycle
    /// @param amount The amount pulled from the {Space} to the treasury
    /// @param paidUntil The timestamp until which the subscription is paid (`start + (cycle + 1) * interval`)
    event SubscriptionCharged(
        address indexed space, bytes32 indexed subscriptionId, uint256 indexed cycle, uint128 amount, uint40 paidUntil
    );

    /// @notice Emitted when a {Space} cancels a subscription
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The unique identifier of the canceled subscription
    event SubscriptionCanceled(address indexed space, bytes32 indexed subscriptionId);

    /// @notice Emitted when the owner updates the treasury address
    /// @param oldTreasury The previous treasury address
    /// @param newTreasury The new treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the treasury address that receives all subscription charges
    function treasury() external view returns (address);

    /// @notice Returns whether the `cycle` of the `subscriptionId` subscription has already been charged
    /// @param subscriptionId The unique identifier of the subscription
    /// @param cycle The zero-based index of the cycle
    function isCharged(bytes32 subscriptionId, uint256 cycle) external view returns (bool);

    /// @notice Retrieves the stored terms and lifecycle status of the `subscriptionId` subscription
    /// @param subscriptionId The unique identifier of the subscription
    /// @return subscription The stored subscription terms
    /// @return status The current lifecycle state (`NotSubscribed`, `Subscribed` or `Canceled`)
    function getSubscription(bytes32 subscriptionId)
        external
        view
        returns (Types.Subscription memory subscription, Types.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Records a {Space}'s consent to a recurring subscription on-chain
    ///
    /// Requirements:
    /// - `msg.sender` must equal `subscription.space` (consent is proven by `Space.execute`'s `onlyAdminOrEntrypoint` gate)
    /// - the derived `subscriptionId` must not already exist
    ///
    /// Notes:
    /// - the {Space} is expected to approve this module for `amount * periods` of `subscription.asset` at subscribe time
    ///
    /// @param subscription The subscription terms following the {Subscription} struct format
    /// @return subscriptionId The unique identifier of the subscription, derived as `keccak256(abi.encode(subscription))`
    function subscribe(Types.Subscription calldata subscription) external returns (bytes32 subscriptionId);

    /// @notice Pulls one cycle's fixed charge from the payer {Space} to the treasury
    ///
    /// Requirements:
    /// - the `subscriptionId` subscription must exist and not be canceled
    /// - the `cycle` must not have been charged before
    /// - the `cycle` must be due (`block.timestamp >= start + cycle * interval`)
    /// - the `cycle` must be within bounds (`cycle < periods`)
    /// - the {Space} must have approved this module for at least `amount` of the asset
    ///
    /// Notes:
    /// - permissionless: any caller can trigger an already-consented charge, but funds always go to the
    /// treasury and the amount is pinned in the stored terms, so it cannot be abused
    ///
    /// @param subscriptionId The unique identifier of the subscription
    /// @param cycle The zero-based index of the cycle to charge
    function charge(bytes32 subscriptionId, uint256 cycle) external;

    /// @notice Cancels a subscription, preventing any further charges
    ///
    /// Requirements:
    /// - `msg.sender` must equal the `space` of the stored subscription
    ///
    /// @param subscriptionId The unique identifier of the subscription to cancel
    function cancel(bytes32 subscriptionId) external;

    /// @notice Updates the treasury address that receives all subscription charges
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newTreasury The new treasury address
    function setTreasury(address newTreasury) external;
}
