// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ISubscriptionModule } from "./interfaces/ISubscriptionModule.sol";
import { Types } from "./libraries/Types.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title SubscriptionModule
/// @notice See the documentation in {ISubscriptionModule}
contract SubscriptionModule is ISubscriptionModule, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "1.0.0";

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.SubscriptionModule
    struct SubscriptionModuleStorage {
        /// @notice The trusted backend signer whose signature authorizes the inputs at {subscribe}
        address signer;
        /// @notice The treasury address that receives all subscription charges
        address treasury;
        /// @notice Subscription details mapped by their `subscriptionId`
        mapping(bytes32 subscriptionId => Types.Subscription) subscriptions;
        /// @notice Whether a `(subscriptionId, cycle)` pair has already been charged
        mapping(bytes32 subscriptionId => mapping(uint256 cycle => bool)) charged;
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
    /// @param _initialAdmin The initial owner of the module (manages the signer, the treasury and upgrades)
    /// @param _signer The initial trusted backend signer whose signature authorizes the inputs at {subscribe}
    /// @param _treasury The initial treasury address that receives all subscription charges
    function initialize(address _initialAdmin, address _signer, address _treasury) public initializer {
        __Ownable_init(_initialAdmin);
        __UUPSUpgradeable_init();

        // Checks: the signer is not the zero address
        if (_signer == address(0)) revert Errors.InvalidZeroAddressSigner();

        // Checks: the treasury is not the zero address
        if (_treasury == address(0)) revert Errors.InvalidZeroAddressTreasury();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Effects: set the initial signer and treasury addresses
        $.signer = _signer;
        $.treasury = _treasury;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function getSigner() external view returns (address) {
        return _getSubscriptionModuleStorage().signer;
    }

    /// @inheritdoc ISubscriptionModule
    function getTreasury() external view returns (address) {
        return _getSubscriptionModuleStorage().treasury;
    }

    /// @inheritdoc ISubscriptionModule
    function isCharged(bytes32 subscriptionId, uint256 cycle) external view returns (bool) {
        return _getSubscriptionModuleStorage().charged[subscriptionId][cycle];
    }

    /// @inheritdoc ISubscriptionModule
    function getSubscription(bytes32 subscriptionId) external view returns (Types.Subscription memory subscription) {
        return _getSubscriptionModuleStorage().subscriptions[subscriptionId];
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function subscribe(Types.SubscribeInput calldata input, bytes calldata signature) external {
        // Checks: the caller is the {Space} declared in the inputs
        // Note: admin's consent is already proven by `Space.executeBatch`'s `onlyAdminOrEntrypoint` modifier
        if (msg.sender != input.space) revert Errors.OnlySubscriptionSpace();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the backend signed these exact inputs for this chain (input integrity)
        // Note: `block.chainid` is included to prevent cross-chain replay
        _verifySubscriptionSignature(input, signature, $.signer);

        // Checks: the subscription does not already exist
        if ($.subscriptions[input.subscriptionId].status != Types.Status.NotRegistered) {
            revert Errors.SubscriptionAlreadyExists();
        }

        // Pin the start to the current timestamp
        uint40 start = uint40(block.timestamp);

        // Effects: pin the full subscription details and mark it as active
        // Note: `amount` is snapshotted here so a future pricing change will not affect ongoing subscriptions
        $.subscriptions[input.subscriptionId] = Types.Subscription({
            space: input.space,
            interval: input.interval,
            periods: input.periods,
            start: start,
            asset: input.asset,
            tier: input.tier,
            status: Types.Status.Active,
            amount: input.amount
        });

        // Log the subscription creation
        emit Subscribed({
            space: input.space,
            subscriptionId: input.subscriptionId,
            tier: input.tier,
            asset: input.asset,
            amount: input.amount,
            interval: input.interval,
            periods: input.periods,
            start: start
        });
    }

    /// @inheritdoc ISubscriptionModule
    function charge(bytes32 subscriptionId, uint256 cycle) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the full subscription details
        // Note: `amount` is read from storage. Any later backend price change cannot affect the
        // already-registered subscription
        Types.Subscription memory subscription = $.subscriptions[subscriptionId];

        // Checks: the subscription is registered (i.e. not in the default `NotRegistered` state)
        if (subscription.status == Types.Status.NotRegistered) revert Errors.SubscriptionNotActive();

        // Checks: the subscription is not revoked
        if (subscription.status == Types.Status.Revoked) revert Errors.SubscriptionRevoked();

        // Checks: the `(subscriptionId, cycle)` pair has not already been charged
        // Note: a per-cycle replay flag (not a single nonce) is used so the relayer can retry or submit
        // cycles out of order
        if ($.charged[subscriptionId][cycle]) revert Errors.CycleAlreadyCharged();

        // Checks: the cycle is within bounds; the subscription did not end
        if (cycle >= subscription.periods) revert Errors.CycleOutOfBounds();

        // Checks: the cycle is due (cannot be charged early)
        // Note: `start` (uint40) + cycle (uint256) * `interval` (uint40) is computed in 256-bit space,
        // so it cannot overflow for any realistic cycle count
        uint256 cycleStart = uint256(subscription.start) + cycle * uint256(subscription.interval);
        if (block.timestamp < cycleStart) revert Errors.CycleNotDue();

        // Effects: mark the cycle as charged BEFORE the interaction
        $.charged[subscriptionId][cycle] = true;

        // Interactions: pull the pinned cycle amount from the {Space} to the treasury
        // Notes:
        // - the destination is always the stored treasury and the amount is pinned in the terms,
        // which is what makes the permissionless `charge` safe
        // - the {Space} is expected to have approved this module for `amount` * `periods`
        IERC20(subscription.asset)
            .safeTransferFrom({ from: subscription.space, to: $.treasury, value: subscription.amount });

        // Compute the timestamp until which the subscription is now paid (start of the next cycle)
        uint40 paidUntil = uint40(cycleStart + subscription.interval);

        // Log the successful charge
        emit SubscriptionCharged(subscription.space, subscriptionId, cycle, subscription.amount, paidUntil);
    }

    /// @inheritdoc ISubscriptionModule
    function revoke(bytes32 subscriptionId) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the subscription details
        Types.Subscription storage subscription = $.subscriptions[subscriptionId];

        // Checks: the subscription is currently active
        if (subscription.status != Types.Status.Active) revert Errors.SubscriptionNotActive();

        // Checks: the caller is the {Space} that subscribed
        // Note: the {Space} calls this via `Space.execute`, which is admin-gated
        if (msg.sender != subscription.space) revert Errors.OnlySubscriptionSpace();

        // Effects: mark the subscription as revoked
        subscription.status = Types.Status.Revoked;

        // Log the subscription revocation
        emit Revoked(msg.sender, subscriptionId);
    }

    /// @inheritdoc ISubscriptionModule
    function setSignerAddress(address newSigner) external onlyOwner {
        // Checks: the new signer is not the zero address
        if (newSigner == address(0)) revert Errors.InvalidZeroAddressSigner();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Cache the old signer for the event
        address oldSigner = $.signer;

        // Effects: update the signer address
        $.signer = newSigner;

        // Log the signer update
        emit SignerUpdated(oldSigner, newSigner);
    }

    /// @inheritdoc ISubscriptionModule
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
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Verifies that the trusted backend signed the subscription inputs for this chain
    function _verifySubscriptionSignature(
        Types.SubscribeInput calldata input,
        bytes calldata signature,
        address signer
    )
        internal
        view
    {
        // Rebuild the message hash the backend produced off-chain over the signed inputs and this chain id
        bytes32 rawHash = keccak256(
            abi.encode(
                input.subscriptionId,
                input.space,
                input.tier,
                input.asset,
                input.amount,
                input.interval,
                input.periods,
                block.chainid
            )
        );

        // Apply the EIP-191 prefix
        bytes32 signedHash = rawHash.toEthSignedMessageHash();

        // Recover the signer and check it matches the trusted backend signer
        if (signedHash.recover(signature) != signer) revert Errors.InvalidBackendSignature();
    }
}
