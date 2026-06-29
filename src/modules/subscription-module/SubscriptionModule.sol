// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ISubscriptionModule } from "./interfaces/ISubscriptionModule.sol";
import { Types } from "./libraries/Types.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title SubscriptionModule
/// @notice See the documentation in {ISubscriptionModule}
contract SubscriptionModule is ISubscriptionModule, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "1.0.0";

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.SubscriptionModule
    struct SubscriptionModuleStorage {
        /// @notice Subscription terms mapped by their `subscriptionId`
        mapping(bytes32 subscriptionId => Types.Subscription) subscriptions;
        /// @notice State of a subscription, mapped by its `subscriptionId`
        mapping(bytes32 subscriptionId => Types.Status) status;
        /// @notice Whether a `(subscriptionId, cycle)` pair has already been charged
        mapping(bytes32 subscriptionId => mapping(uint256 cycle => bool)) charged;
        /// @notice The treasury address that receives all subscription charges
        address treasury;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.SubscriptionModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SUBSCRIPTION_MODULE_STORAGE_LOCATION =
        0xa152dff672fc6d0a5dc0a233c59a5b34d690154ac389739e5bcf1c0410662500;

    /// @dev Retrieves the storage of the {SubscriptionModule} contract
    function _getSubscriptionModuleStorage() internal pure returns (SubscriptionModuleStorage storage $) {
        assembly {
            $.slot := SUBSCRIPTION_MODULE_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the proxy and the {Ownable} contract
    /// @param _initialAdmin The initial owner of the module (manages the treasury and upgrades)
    /// @param _treasury The initial treasury address that receives all subscription charges
    function initialize(address _initialAdmin, address _treasury) public initializer {
        __Ownable_init(_initialAdmin);
        __UUPSUpgradeable_init();

        // Checks: the treasury is not the zero address
        if (_treasury == address(0)) revert Errors.InvalidZeroAddressTreasury();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Effects: set the initial treasury address
        $.treasury = _treasury;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function treasury() external view returns (address) {
        return _getSubscriptionModuleStorage().treasury;
    }

    /// @inheritdoc ISubscriptionModule
    function isCharged(bytes32 subscriptionId, uint256 cycle) external view returns (bool) {
        return _getSubscriptionModuleStorage().charged[subscriptionId][cycle];
    }

    /// @inheritdoc ISubscriptionModule
    function getSubscription(bytes32 subscriptionId)
        external
        view
        returns (Types.Subscription memory subscription, Types.Status status)
    {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        return ($.subscriptions[subscriptionId], $.status[subscriptionId]);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function subscribe(Types.Subscription calldata subscription) external returns (bytes32 subscriptionId) {
        // Checks: the caller is the {Space} declared in the terms
        // Note: admin's consent is already proven by `Space.execute`'s `onlyAdminOrEntrypoint` modifier
        if (msg.sender != subscription.space) revert Errors.OnlySubscriptionSpace();

        // Derive the unique subscription identifier from the full terms
        subscriptionId = keccak256(abi.encode(subscription));

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the subscription does not already exist
        if ($.status[subscriptionId] != Types.Status.NotSubscribed) revert Errors.SubscriptionAlreadyExists();

        // Effects: store the full terms and mark the subscription as active
        $.subscriptions[subscriptionId] = subscription;
        $.status[subscriptionId] = Types.Status.Subscribed;

        // Log the subscription creation
        emit Subscribed({
            space: subscription.space,
            subscriptionId: subscriptionId,
            tier: subscription.tier,
            asset: subscription.asset,
            amount: subscription.amount,
            interval: subscription.interval,
            periods: subscription.periods,
            start: subscription.start
        });
    }

    /// @inheritdoc ISubscriptionModule
    function charge(bytes32 subscriptionId, uint256 cycle) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the current subscription status
        Types.Status status = $.status[subscriptionId];

        // Checks: the subscription exists (i.e. not in the default `NotSubscribed` state)
        if (status == Types.Status.NotSubscribed) revert Errors.SubscriptionNotFound();

        // Checks: the subscription is not canceled
        if (status == Types.Status.Canceled) revert Errors.SubscriptionCanceled();

        // Checks: the `(subscriptionId, cycle)` pair has not already been charged
        // Note: a per-cycle replay flag (not a single nonce) is used so the relayer can retry or submit
        // cycles out of order without colliding
        if ($.charged[subscriptionId][cycle]) revert Errors.CycleAlreadyCharged();

        // Load the stored terms
        Types.Subscription memory subscription = $.subscriptions[subscriptionId];

        // Checks: the cycle is within bounds; subscription did not end
        if (cycle >= subscription.periods) revert Errors.CycleOutOfBounds();

        // Checks: the cycle is due (cannot be charged early)
        // Note: `start` (uint40) + cycle (uint256) * `interval` (uint40) is computed in 256-bit space,
        // so it cannot overflow for any realistic cycle count
        uint256 cycleStart = uint256(subscription.start) + cycle * uint256(subscription.interval);
        if (block.timestamp < cycleStart) revert Errors.CycleNotDue();

        // Effects: mark the cycle as charged BEFORE the interaction
        $.charged[subscriptionId][cycle] = true;

        // Interactions: pull the fixed cycle amount from the {Space} to the treasury
        // Notes:
        // - the destination is ALWAYS the stored treasury and the amount is pinned in the terms,
        // which is what makes the permissionless `charge` safe
        // - the treasury is pre approved for spending `amount` * `periods`
        IERC20(subscription.asset)
            .safeTransferFrom({ from: subscription.space, to: $.treasury, value: subscription.amount });

        // Compute the timestamp until which the subscription is now paid (start of the next cycle)
        uint40 paidUntil = uint40(cycleStart + subscription.interval);

        // Log the successful charge
        emit SubscriptionCharged(subscription.space, subscriptionId, cycle, subscription.amount, paidUntil);
    }

    /// @inheritdoc ISubscriptionModule
    function cancel(bytes32 subscriptionId) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the caller is the {Space} that created the subscription
        if (msg.sender != $.subscriptions[subscriptionId].space) revert Errors.OnlySubscriptionSpace();

        // Checks: the subscription is currently active (cannot re-cancel an already-canceled one)
        if ($.status[subscriptionId] == Types.Status.Canceled) revert Errors.SubscriptionCanceled();

        // Effects: mark the subscription as canceled
        $.status[subscriptionId] = Types.Status.Canceled;

        // Log the subscription revocation
        emit SubscriptionCanceled(msg.sender, subscriptionId);
    }

    /// @inheritdoc ISubscriptionModule
    /// @dev Trusted owner action: the treasury receives ALL subscription charges, so the owner should be
    /// hardened with a multisig and/or timelock to prevent a single key from redirecting funds
    function setTreasury(address newTreasury) external onlyOwner {
        // Checks: the new treasury is not the zero address
        if (newTreasury == address(0)) revert Errors.InvalidZeroAddressTreasury();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Cache the old treasury for the event
        address oldTreasury = $.treasury;

        // Effects: update the treasury address
        $.treasury = newTreasury;

        // Log the treasury update
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
}
