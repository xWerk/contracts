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

    /// @dev The maximum number of billing cycles, bounded by the width of the charge bitmap
    uint256 private constant MAX_PERIODS = 256;

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.SubscriptionModule
    struct SubscriptionModuleStorage {
        /// @notice Owner-managed pricing per tier
        mapping(uint8 tier => Types.TierConfig) tierConfigs;
        /// @notice Owner-managed allowlist of ERC-20 assets accepted for new subscriptions
        mapping(address asset => bool) allowedAssets;
        /// @notice The subscription (terms + status) of a {Space}, mapped by the {Space} address
        /// @dev A never-subscribed {Space} has a zero struct whose `status` is `NotSubscribed`, which
        /// doubles as the "no subscription" existence check
        mapping(address space => Types.Subscription) subscriptions;
        /// @notice Bitmap of charged cycles for a {Space}'s current subscription
        /// @dev Reset to zero on each (re)subscribe so a new subscription starts with a clean history
        mapping(address space => uint256) chargedBitmap;
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
    /// @param _initialAdmin The initial owner of the module (manages tiers, assets, treasury and upgrades)
    /// @param _treasury The initial treasury address that receives all subscription charges
    /// @param _initialAsset The initial allowlisted ERC-20 payment asset (e.g. USDC)
    function initialize(address _initialAdmin, address _treasury, address _initialAsset) public initializer {
        __Ownable_init(_initialAdmin);
        __UUPSUpgradeable_init();

        // Checks: the treasury and initial asset are not the zero address
        if (_treasury == address(0)) revert Errors.InvalidZeroAddressTreasury();
        if (_initialAsset == address(0)) revert Errors.InvalidZeroAddressAsset();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Effects: set the initial treasury and allowlist the initial asset
        $.treasury = _treasury;
        $.allowedAssets[_initialAsset] = true;

        // Log the initial asset allowlisting
        emit AssetAllowed(_initialAsset, true);
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
    function isAssetAllowed(address asset) external view returns (bool) {
        return _getSubscriptionModuleStorage().allowedAssets[asset];
    }

    /// @inheritdoc ISubscriptionModule
    function getTierConfig(uint8 tier) external view returns (Types.TierConfig memory config) {
        return _getSubscriptionModuleStorage().tierConfigs[tier];
    }

    /// @inheritdoc ISubscriptionModule
    function isCharged(address space, uint256 cycle) external view returns (bool) {
        return _getSubscriptionModuleStorage().chargedBitmap[space] & (1 << cycle) != 0;
    }

    /// @inheritdoc ISubscriptionModule
    function getSubscription(address space) external view returns (Types.Subscription memory subscription) {
        return _getSubscriptionModuleStorage().subscriptions[space];
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OWNER NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function setTier(uint8 tier, uint128 amount, uint40 interval) external onlyOwner {
        // Checks: the pricing values are non-zero
        if (amount == 0) revert Errors.InvalidTierAmount();
        if (interval == 0) revert Errors.InvalidTierInterval();

        // Effects: store the tier pricing configuration
        _getSubscriptionModuleStorage().tierConfigs[tier] = Types.TierConfig({ amount: amount, interval: interval });

        // Log the tier configuration
        emit TierConfigured(tier, amount, interval);
    }

    /// @inheritdoc ISubscriptionModule
    function removeTier(uint8 tier) external onlyOwner {
        // Effects: clear the tier pricing configuration, disabling new subscriptions to it
        delete _getSubscriptionModuleStorage().tierConfigs[tier];

        // Log the tier removal
        emit TierRemoved(tier);
    }

    /// @inheritdoc ISubscriptionModule
    function setAssetAllowed(address asset, bool allowed) external onlyOwner {
        // Checks: the asset is not the zero address
        if (asset == address(0)) revert Errors.InvalidZeroAddressAsset();

        // Effects: update the asset allowlist (only affects NEW subscriptions)
        _getSubscriptionModuleStorage().allowedAssets[asset] = allowed;

        // Log the allowlist update
        emit AssetAllowed(asset, allowed);
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

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function subscribe(uint8 tier, address asset, uint16 periods, uint40 start) external {
        // The paying {Space} is the caller; consent is proven by `Space.execute`'s `onlyAdminOrEntrypoint` modifier
        address space = msg.sender;

        // Checks: `periods` is within the supported range
        if (periods == 0 || periods > MAX_PERIODS) revert Errors.InvalidPeriods();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the asset is allowlisted
        if (!$.allowedAssets[asset]) revert Errors.AssetNotAllowed();

        // Checks: the tier is configured
        Types.TierConfig memory config = $.tierConfigs[tier];
        if (config.amount == 0) revert Errors.InvalidTier();

        // Checks: the {Space} does not already hold an active subscription
        if ($.subscriptions[space].status == Types.Status.Subscribed) revert Errors.SubscriptionAlreadyActive();

        // Effects: snapshot the price and cadence from the tier config, record the chosen asset, mark the
        // subscription active and reset the charge history
        $.subscriptions[space] = Types.Subscription({
            amount: config.amount,
            interval: config.interval,
            start: start,
            periods: periods,
            tier: tier,
            status: Types.Status.Subscribed,
            asset: asset
        });
        $.chargedBitmap[space] = 0;

        // Log the subscription
        emit Subscribed(space, tier, asset, config.amount, config.interval, periods, start);
    }

    /// @inheritdoc ISubscriptionModule
    function charge(address space, uint256 cycle) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the stored subscription (terms + status)
        Types.Subscription memory subscription = $.subscriptions[space];

        // Checks: the {Space} has a subscription
        if (subscription.status == Types.Status.NotSubscribed) revert Errors.SubscriptionNotFound();

        // Checks: the subscription is not canceled
        if (subscription.status == Types.Status.Canceled) revert Errors.SubscriptionCanceled();

        // Checks: the cycle is within bounds; subscription did not end
        // Note: `periods <= MAX_PERIODS` (256), so `cycle < periods` guarantees `1 << cycle` does not overflow
        if (cycle >= subscription.periods) revert Errors.CycleOutOfBounds();

        // Checks: the cycle has not already been charged
        // Note: a per-cycle bitmap (not a single nonce) is used so the relayer can retry or submit
        // cycles out of order without colliding
        uint256 cycleBit = 1 << cycle;
        if ($.chargedBitmap[space] & cycleBit != 0) revert Errors.CycleAlreadyCharged();

        // Checks: the cycle is due (cannot be charged early)
        // Note: `start` (uint40) + cycle (uint256) * `interval` (uint40) is computed in 256-bit space,
        // so it cannot overflow for any realistic cycle count
        uint256 cycleStart = uint256(subscription.start) + cycle * uint256(subscription.interval);
        if (block.timestamp < cycleStart) revert Errors.CycleNotDue();

        // Effects: mark the cycle as charged BEFORE the interaction
        $.chargedBitmap[space] |= cycleBit;

        // Interactions: pull the fixed cycle amount from the {Space} to the treasury
        // Notes:
        // - the destination is ALWAYS the stored treasury and the amount is pinned in the terms,
        // which is what makes the permissionless `charge` safe
        // - the {Space} is expected to have pre-approved this module for `amount * periods`
        IERC20(subscription.asset).safeTransferFrom({ from: space, to: $.treasury, value: subscription.amount });

        // Compute the timestamp until which the subscription is now paid (start of the next cycle)
        uint40 paidUntil = uint40(cycleStart + subscription.interval);

        // Log the successful charge
        emit SubscriptionCharged(space, cycle, subscription.amount, paidUntil);
    }

    /// @inheritdoc ISubscriptionModule
    function cancel() external {
        // The {Space} cancels its own subscription
        address space = msg.sender;

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the current lifecycle state
        Types.Status status = $.subscriptions[space].status;

        // Checks: the {Space} has a subscription and it is not already canceled
        if (status == Types.Status.NotSubscribed) revert Errors.SubscriptionNotFound();
        if (status == Types.Status.Canceled) revert Errors.SubscriptionCanceled();

        // Effects: mark the subscription as canceled
        $.subscriptions[space].status = Types.Status.Canceled;

        // Log the cancellation
        emit SubscriptionCanceled(space);
    }
}
