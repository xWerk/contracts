// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title ISubscriptionModule
/// @notice Manages on-chain recurring subscription billing.
/// - Consent: the {Space} itself calls {subscribe} via `Space.executeBatch`, which is gated by the {Space}'s
/// `onlyAdminOrEntrypoint` modifier — so the call is already proven to be admin-authorized. The module only
/// binds it to the right payer via `msg.sender == input.space`
/// - Input integrity: the backend EOA signs the terms and the module verifies thesignature once at {subscribe},
///  pinning `amount` for the life of the subscription (later price changes affect  only new subscriptions)
///
/// @dev The {Space} must approve this module for the full exposure (`amount * periods`) of `asset` before any
/// cycle can be charged; each {charge} pulls `amount` via `safeTransferFrom`.
///
/// The backend generates a unique `subscriptionId` per subscription (the mapping key and same-chain replay
/// guard); `block.chainid` in the signed payload guards cross-chain replay.
interface ISubscriptionModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a {Space} subscribes
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The backend-generated unique identifier of the subscription
    /// @param tier The plan identifier
    /// @param asset The ERC-20 asset used to pay each cycle
    /// @param amount The fixed charge pulled per cycle (pinned at subscribe time)
    /// @param interval The number of seconds between two consecutive cycles
    /// @param periods The total number of cycles
    /// @param start The timestamp at which cycle 0 becomes chargeable
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

    /// @notice Emitted when a {Space} revokes a subscription
    /// @param space The payer {Space} smart account
    /// @param subscriptionId The unique identifier of the revoked subscription
    event Revoked(address indexed space, bytes32 indexed subscriptionId);

    /// @notice Emitted when the owner updates the trusted backend signer address
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @notice Emitted when the owner updates the treasury address
    /// @param oldTreasury The previous treasury address
    /// @param newTreasury The new treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the trusted backend signer whose signature authorizes the inputs at {subscribe}
    function getSigner() external view returns (address);

    /// @notice Retrieves the treasury address that receives all subscription charges
    function getTreasury() external view returns (address);

    /// @notice Returns whether the `cycle` of the `subscriptionId` subscription has already been charged
    /// @dev Cycles are charged strictly in order, so this is equivalent to `cycle < chargedCount`
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
    /// - `Expired` if all `periods` cycles have been charged (natural end)
    /// - `PastDue` if more cycles have started than have been charged (a payment is overdue)
    /// - `Active` otherwise (paid up to, or still within, the current cycle)
    ///
    /// @param subscriptionId The unique identifier of the subscription
    /// @return status The derived lifecycle state
    function statusOf(bytes32 subscriptionId) external view returns (Types.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Records a {Space}'s consent to a backend-signed recurring subscription on-chain
    ///
    /// Requirements:
    /// - `msg.sender` must equal `input.space` (consent is proven by `Space.executeBatch`'s `onlyAdminOrEntrypoint` gate)
    /// - the signed terms must not have expired (`block.timestamp <= input.validUntil`)
    /// - the backend signature must recover to the stored signer over
    ///   `keccak256(abi.encode(subscriptionId, space, tier, asset, amount, interval, periods, validUntil, block.chainid))`
    ///   wrapped with the EIP-191 prefix (input integrity)
    /// - `input.subscriptionId` must not already be registered
    ///
    /// Notes:
    /// - the {Space} is expected to approve this module for `amount * periods` of `input.asset` at subscribe time
    /// - the stored `start` is set to `block.timestamp`
    /// - the stored `amount` is pinned: {charge} reads it for the life of the subscription and a later backend
    /// price change does NOT affect this subscription
    ///
    /// @param input The backend-signed subscription inputs following the {SubscribeInput} struct format
    /// @param signature The backend EIP-191 signature over the signed payload
    function subscribe(Types.SubscribeInput calldata input, bytes calldata signature) external;

    /// @notice Pulls the next cycle's pinned charge from the payer {Space} to the treasury
    ///
    /// Cycles are charged strictly in order: the next chargeable cycle is always `chargedCount`
    ///
    /// Requirements:
    /// - the `subscriptionId` subscription must be registered and not revoked
    /// - the subscription must not have reached its natural end (`chargedCount < periods`)
    /// - the next cycle must be due (`block.timestamp >= start + chargedCount * interval`)
    /// - the {Space} must have approved this module for at least `amount` of the asset
    ///
    /// Notes:
    /// - permissionless: any caller (typically the backend relayer) can trigger an already-consented charge.
    /// Funds always go to the stored treasury and the amount is the pinned per-cycle `amount`, so a random
    /// caller can only trigger a legitimate charge
    /// - No signature or admin check needed: billing depends only on the stored consent, so it survives
    /// {Space} admin rotation
    /// - Prevent double charge: each successful charge increments `chargedCount`, pushing the next due time one
    /// `interval` ahead, so a repeated call reverts with {CycleNotDue} until the next cycle actually starts.
    /// Consecutive calls only succeed while the subscription is catching up, never twice per cycle
    /// - once `chargedCount` reaches `periods`, {statusOf} derives `Expired`
    ///
    /// @param subscriptionId The unique identifier of the subscription
    function charge(bytes32 subscriptionId) external;

    /// @notice Revokes a subscription, preventing any further charges
    ///
    /// Requirements:
    /// - the `subscriptionId` subscription must be currently active
    /// - `msg.sender` must equal the `space` of the stored subscription
    ///
    /// @param subscriptionId The unique identifier of the subscription to revoke
    function revoke(bytes32 subscriptionId) external;

    /// @notice Rotates the trusted backend signer address
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newSigner The new signer address
    function setSignerAddress(address newSigner) external;

    /// @notice Updates the treasury address that receives all subscription charges
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner
    ///
    /// @param newTreasury The new treasury address
    function setTreasury(address newTreasury) external;
}
