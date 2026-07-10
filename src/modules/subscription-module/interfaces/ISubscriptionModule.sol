// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title ISubscriptionModule
/// @notice Manages on-chain recurring subscription billing.
/// - Consent: the {Space} itself calls {subscribe} via `Space.executeBatch`, which is gated by the {Space}'s
/// `onlyAdminOrEntrypoint` modifier — so the call is already proven to be admin-authorized. The module only
/// binds it to the right payer via `msg.sender == input.space`
/// - Input integrity: the trusted relayer (an EOA held by the backend) signs the terms and the module verifies
/// the signature once at {subscribe}. The per-cycle price is NOT part of the terms: it is supplied by the
/// relayer at {charge} time, so Werk can change the price over the life of a subscription (after notifying the
/// payer off-chain) without re-consenting on-chain
///
/// @dev The {Space} must approve this module for the buffered exposure of `asset` before any cycle can be
/// charged; each {charge} pulls a relayer-supplied `amount` via `safeTransferFrom`. Approving a buffer above
/// the current price lets a moderate price increase be charged without a new approval.
///
/// The backend generates a unique `subscriptionId` per subscription (the mapping key and same-chain replay
/// guard); `block.chainid` in the signed payload guards cross-chain replay. Relayer is the only
/// address allowed to call {charge}.
interface ISubscriptionModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a {Space} subscribes
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The backend-generated unique identifier of the subscription
    /// @param asset The ERC-20 asset used to pay each cycle
    /// @param interval The number of seconds between two consecutive cycles
    /// @param cycles The total number of cycles
    /// @param start The timestamp at which cycle 0 becomes chargeable
    event Subscribed(
        address indexed space,
        bytes32 indexed subscriptionId,
        address asset,
        uint40 interval,
        uint16 cycles,
        uint40 start
    );

    /// @notice Emitted when a cycle is successfully charged
    /// @param space The payer {Space} smart account that was charged
    /// @param subscriptionId The unique identifier of the subscription
    /// @param cycle The zero-based index of the charged cycle
    /// @param amount The relayer-supplied amount pulled from the {Space} to the treasury for this cycle
    /// @param paidUntil The timestamp until which the subscription is paid (`start + (cycle + 1) * interval`)
    event SubscriptionCharged(
        address indexed space, bytes32 indexed subscriptionId, uint256 indexed cycle, uint128 amount, uint40 paidUntil
    );

    /// @notice Emitted when a {Space} revokes a subscription
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The unique identifier of the revoked subscription
    event Revoked(address indexed space, bytes32 indexed subscriptionId);

    /// @notice Emitted when the owner updates the trusted relayer address
    /// @param oldRelayer The previous relayer address
    /// @param newRelayer The new relayer address
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);

    /// @notice Emitted when the owner updates the treasury address
    /// @param oldTreasury The previous treasury address
    /// @param newTreasury The new treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the trusted relayer: the address whose signature authorizes the inputs at {subscribe}
    /// and the only address allowed to call {charge}
    function getRelayer() external view returns (address);

    /// @notice Retrieves the treasury address that receives all subscription charges
    function getTreasury() external view returns (address);

    /// @notice Returns whether the `cycle` of the `subscriptionId` subscription has already been charged
    /// @dev Cycles are charged strictly in order, so this is equivalent to `cycle < cyclesCharged`
    /// @param subscriptionId The unique identifier of the subscription
    /// @param cycle The zero-based index of the cycle
    function isCharged(bytes32 subscriptionId, uint256 cycle) external view returns (bool);

    /// @notice Retrieves the full pinned details of the `subscriptionId` subscription
    /// @param subscriptionId The unique identifier of the subscription
    /// @return subscription The pinned subscription details
    function getSubscription(bytes32 subscriptionId) external view returns (Types.Subscription memory subscription);

    /// @notice Derives the current status of the `subscriptionId` subscription
    ///
    /// The status is never stored; it is computed on demand from the stored fields and `block.timestamp`:
    /// - `Null` if the subscription was never registered
    /// - `Revoked` if the {Space} revoked it (charging permanently disabled)
    /// - `Expired` if all `cycles` have been charged (natural end)
    /// - `PastDue` if more cycles have started than have been charged (a payment is overdue)
    /// - `Active` otherwise (paid up to, or still within, the current cycle)
    ///
    /// @param subscriptionId The unique identifier of the subscription
    /// @return status The derived lifecycle state
    function statusOf(bytes32 subscriptionId) external view returns (Types.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Records a {Space}'s consent to a relayer-signed recurring subscription on-chain
    ///
    /// Requirements:
    /// - `msg.sender` must equal `input.space` (consent is proven by `Space.executeBatch`'s `onlyAdminOrEntrypoint` gate)
    /// - the signed terms must not have expired (`block.timestamp <= input.validUntil`)
    /// - the relayer signature must recover to the stored relayer over
    ///   `keccak256(abi.encode(subscriptionId, space, asset, interval, cycles, validUntil, block.chainid))`
    ///   wrapped with the EIP-191 prefix (input integrity)
    /// - `input.subscriptionId` must not already be registered
    ///
    /// Notes:
    /// - the {Space} is expected to approve this module for the buffered exposure of `input.asset` at subscribe time
    /// - the stored `start` is set to `block.timestamp`
    /// - no price is stored: {charge} pulls a relayer-supplied `amount`, so a later price change does not require
    /// re-subscribing; the `asset` is pinned so every charge is bound to the token the {Space} approved
    ///
    /// @param input The relayer-signed subscription inputs following the {SubscribeInput} struct format
    /// @param signature The relayer EIP-191 signature over the signed payload
    function subscribe(Types.SubscribeInput calldata input, bytes calldata signature) external;

    /// @notice Pulls the next cycle's charge from the payer {Space} to the treasury
    ///
    /// Cycles are charged strictly in order: the next chargeable cycle is always `cyclesCharged`
    ///
    /// Requirements:
    /// - `msg.sender` must be the trusted relayer (or the module itself, via {chargeBatch})
    /// - the `subscriptionId` subscription must be registered and not revoked
    /// - the subscription must not have reached its natural end (`cyclesCharged < cycles`)
    /// - the next cycle must be due (`block.timestamp >= start + cyclesCharged * interval`)
    /// - the {Space} must have approved this module for at least `amount` of the pinned asset
    ///
    /// Notes:
    /// - relayer-only: the caller supplies the per-cycle `amount`, so it must be the trusted relayer. Funds always
    /// go to the stored treasury and the token is the pinned `asset`; only the `amount` varies per cycle, which is
    /// how Werk applies a price change (charge a different amount on the next cycle)
    /// - Prevent double charge: each successful charge increments `cyclesCharged`, pushing the next due time one
    /// `interval` ahead, so a repeated call reverts with {CycleNotDue} until the next cycle actually starts.
    /// Consecutive calls only succeed while the subscription is catching up, never twice per cycle
    /// - once `cyclesCharged` reaches `cycles`, {statusOf} derives `Expired`
    ///
    /// @param subscriptionId The unique identifier of the subscription
    /// @param amount The amount to pull from the {Space} for this cycle (relayer-supplied)
    function charge(bytes32 subscriptionId, uint128 amount) external;

    /// @notice Charges the next due cycle of multiple subscriptions in a single transaction
    ///
    /// Each item is isolated in an external self-call (`try this.charge(...)`), so one failing charge will not
    //  revert the rest of the batch. A failed item remains due, so the relayer simply retries it on a later run
    ///
    /// Requirements:
    /// - `msg.sender` must be the trusted relayer
    /// - `subscriptionIds` and `amounts` must have the same length
    ///
    /// @param subscriptionIds The unique identifiers of the subscriptions to charge, in order
    /// @param amounts The amount to pull for each subscription
    function chargeBatch(bytes32[] calldata subscriptionIds, uint128[] calldata amounts) external;

    /// @notice Revokes a subscription, preventing any further charges
    ///
    /// Requirements:
    /// - the `subscriptionId` subscription must be currently active
    /// - `msg.sender` must equal the `space` of the stored subscription
    ///
    /// @param subscriptionId The unique identifier of the subscription to revoke
    function revoke(bytes32 subscriptionId) external;

    /// @notice Rotates the trusted relayer address
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newRelayer The new relayer address
    function setRelayer(address newRelayer) external;

    /// @notice Updates the treasury address that receives all subscription charges
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newTreasury The new treasury address
    function setTreasury(address newTreasury) external;
}
