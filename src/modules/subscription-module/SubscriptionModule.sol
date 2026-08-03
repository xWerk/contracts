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
        /// @notice The trusted relayer: the backend address whose signature authorizes the inputs at {subscribe}
        /// and the only address allowed to call {charge}
        address relayer;
        /// @notice The treasury address that receives all subscription charges
        address treasury;
        /// @notice Subscription details mapped by their `subscriptionId`
        mapping(bytes32 subscriptionId => Types.Subscription) subscriptions;
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
    /// @param _initialAdmin The initial owner of the module (manages the relayer, the treasury and upgrades)
    /// @param _relayer The initial trusted relayer whose signature authorizes the inputs at {subscribe} and who
    /// is the only address allowed to call {charge}
    /// @param _treasury The initial treasury address that receives all subscription charges
    function initialize(address _initialAdmin, address _relayer, address _treasury) public initializer {
        __Ownable_init(_initialAdmin);
        __UUPSUpgradeable_init();

        // Checks: the relayer is not the zero address
        if (_relayer == address(0)) revert Errors.InvalidZeroAddressRelayer();

        // Checks: the treasury is not the zero address
        if (_treasury == address(0)) revert Errors.InvalidZeroAddressTreasury();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Effects: set the initial relayer and treasury addresses
        $.relayer = _relayer;
        $.treasury = _treasury;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function getRelayer() external view returns (address) {
        return _getSubscriptionModuleStorage().relayer;
    }

    /// @inheritdoc ISubscriptionModule
    function getTreasury() external view returns (address) {
        return _getSubscriptionModuleStorage().treasury;
    }

    /// @inheritdoc ISubscriptionModule
    function isCharged(bytes32 subscriptionId, uint256 cycle) external view returns (bool) {
        // Cycles are charged strictly in order, so a cycle is charged if it is below the charged-cycle count
        return cycle < _getSubscriptionModuleStorage().subscriptions[subscriptionId].cyclesCharged;
    }

    /// @inheritdoc ISubscriptionModule
    function getSubscription(bytes32 subscriptionId) external view returns (Types.Subscription memory subscription) {
        return _getSubscriptionModuleStorage().subscriptions[subscriptionId];
    }

    /// @inheritdoc ISubscriptionModule
    function statusOf(bytes32 subscriptionId) external view returns (Types.Status status) {
        // Load the subscription details
        Types.Subscription memory subscription = _getSubscriptionModuleStorage().subscriptions[subscriptionId];

        // If the subscription was never registered, return `Null`
        // Note: a registered subscription always has a non-zero `space`
        if (subscription.space == address(0)) {
            return Types.Status.Null;
        }

        // If the subscription was revoked, return `Revoked`
        if (subscription.isRevoked) {
            return Types.Status.Revoked;
        }

        // If every cycle has been charged, the subscription reached its natural end; return `Expired`
        if (subscription.cyclesCharged == subscription.cycles) {
            return Types.Status.Expired;
        }

        // Compute how many cycles have started as of now, capped at `cycles`
        // Note: cycle `i` starts at `start + i * interval`, so by `block.timestamp` the number of started
        // cycles is `(block.timestamp - start) / interval + 1`; it is `0` while still before `start`
        uint256 elapsedCycles;
        if (block.timestamp >= subscription.start) {
            elapsedCycles = (block.timestamp - subscription.start) / subscription.interval + 1;
            if (elapsedCycles > subscription.cycles) {
                elapsedCycles = subscription.cycles;
            }
        }

        // If more cycles have started than have been charged, a payment is overdue; return `PastDue`
        if (elapsedCycles > subscription.cyclesCharged) {
            return Types.Status.PastDue;
        }

        // Otherwise the subscription is paid up to (or within) the current cycle
        return Types.Status.Active;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISubscriptionModule
    function subscribe(Types.SubscribeInput calldata input, bytes calldata signature) external {
        // Checks: the caller is the {Space} declared in the inputs
        // Note: admin's consent is already proven by `Space.executeBatch`'s `onlyAdminOrEntrypoint` modifier
        if (msg.sender != input.space) revert Errors.OnlySubscriptionSpace();

        // Checks: the signed terms have not expired (a stale quote cannot be redeemed later)
        if (block.timestamp > input.validUntil) revert Errors.SignatureExpired();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the relayer signed these exact inputs for this chain (input integrity)
        // Note: `block.chainid` is included to prevent cross-chain replay
        _verifySubscriptionSignature(input, signature, $.relayer);

        // Checks: the subscription does not already exist
        // Note: a registered subscription always has a non-zero `space`
        if ($.subscriptions[input.subscriptionId].space != address(0)) {
            revert Errors.SubscriptionAlreadyExists();
        }

        // Pin the start to the current timestamp
        uint40 start = uint40(block.timestamp);

        // Effects: pin the full subscription details
        $.subscriptions[input.subscriptionId] = Types.Subscription({
            space: input.space,
            interval: input.interval,
            cycles: input.cycles,
            start: start,
            asset: input.asset,
            isRevoked: false,
            cyclesCharged: 0
        });

        // Log the subscription creation
        emit Subscribed({
            space: input.space,
            subscriptionId: input.subscriptionId,
            asset: input.asset,
            interval: input.interval,
            cycles: input.cycles,
            start: start
        });
    }

    /// @inheritdoc ISubscriptionModule
    function charge(bytes32 subscriptionId, uint128 amount) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Checks: the caller is the trusted relayer, or the module itself.
        if (msg.sender != $.relayer && msg.sender != address(this)) {
            revert Errors.OnlyRelayer();
        }

        // Load the full subscription details
        Types.Subscription memory subscription = $.subscriptions[subscriptionId];

        // Checks: the subscription exists
        if (subscription.space == address(0)) revert Errors.SubscriptionNull();

        // Checks: the subscription is not revoked
        if (subscription.isRevoked) revert Errors.SubscriptionRevoked();

        // Cycles are charged strictly in order: the next chargeable cycle is always the charged-cycle count
        uint256 cycle = subscription.cyclesCharged;

        // Checks: the subscription did not reach its natural end (all cycles charged)
        if (cycle >= subscription.cycles) revert Errors.SubscriptionEnded();

        // Checks: the cycle is due (cannot be charged early)
        uint256 cycleStart = uint256(subscription.start) + cycle * uint256(subscription.interval);
        if (block.timestamp < cycleStart) revert Errors.CycleNotDue();

        // Effects: bump the charged-cycle counter before the interaction
        $.subscriptions[subscriptionId].cyclesCharged = subscription.cyclesCharged + 1;

        // Interactions: pull the relayer-supplied cycle amount from the {Space} to the treasury
        IERC20(subscription.asset).safeTransferFrom({ from: subscription.space, to: $.treasury, value: amount });

        // Compute the timestamp until which the subscription is now paid (start of the next cycle)
        uint40 paidUntil = uint40(cycleStart + subscription.interval);

        // Log the successful charge
        emit SubscriptionCharged(subscription.space, subscriptionId, cycle, amount, paidUntil);
    }

    /// @inheritdoc ISubscriptionModule
    function chargeBatch(bytes32[] calldata subscriptionIds, uint128[] calldata amounts) external {
        // Checks: the caller is the trusted relayer
        if (msg.sender != _getSubscriptionModuleStorage().relayer) revert Errors.OnlyRelayer();

        // Checks: same input array length
        if (subscriptionIds.length != amounts.length) revert Errors.ArrayLengthMismatch();

        // Cache the length so the loop condition does not read it on each iteration
        uint256 subscriptionsLength = subscriptionIds.length;

        for (uint256 i; i < subscriptionsLength; ++i) {
            // Use try/catch block to ensure one failing transaction is silently skipped
            try this.charge(subscriptionIds[i], amounts[i]) { } catch { }
        }
    }

    /// @inheritdoc ISubscriptionModule
    function revoke(bytes32 subscriptionId) external {
        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Load the subscription details
        Types.Subscription storage subscription = $.subscriptions[subscriptionId];

        // Checks: the subscription is registered (a zero `space` is the never-registered sentinel)
        if (subscription.space == address(0)) revert Errors.SubscriptionNull();

        // Checks: the subscription is not already revoked
        if (subscription.isRevoked) revert Errors.SubscriptionRevoked();

        // Checks: the caller is the {Space} that subscribed or the relayer
        // Note: the {Space} calls this via `Space.execute`, which is admin-gated
        if (msg.sender != subscription.space && msg.sender != $.relayer) {
            revert Errors.OnlySpaceOrRelayer();
        }

        // Effects: mark the subscription as revoked
        subscription.isRevoked = true;

        // Log the subscription revocation
        emit Revoked(subscription.space, subscriptionId);
    }

    /// @inheritdoc ISubscriptionModule
    function setRelayer(address newRelayer) external onlyOwner {
        // Checks: the new relayer is not the zero address
        if (newRelayer == address(0)) revert Errors.InvalidZeroAddressRelayer();

        // Retrieve the contract storage
        SubscriptionModuleStorage storage $ = _getSubscriptionModuleStorage();

        // Cache the old relayer for the event
        address oldRelayer = $.relayer;

        // Effects: update the relayer address
        $.relayer = newRelayer;

        // Log the relayer update
        emit RelayerUpdated(oldRelayer, newRelayer);
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

    /// @dev Verifies that the trusted relayer signed the subscription inputs for this chain
    function _verifySubscriptionSignature(
        Types.SubscribeInput calldata input,
        bytes calldata signature,
        address relayer
    )
        internal
        view
    {
        // Rebuild the message hash the relayer produced off-chain over the signed inputs and this chain id
        bytes32 rawHash = keccak256(
            abi.encode(
                input.subscriptionId,
                input.space,
                input.asset,
                input.interval,
                input.cycles,
                input.validUntil,
                block.chainid
            )
        );

        // Apply the EIP-191 prefix
        bytes32 signedHash = rawHash.toEthSignedMessageHash();

        // Recover the signer and check it matches the trusted relayer
        if (signedHash.recover(signature) != relayer) revert Errors.InvalidRelayerSignature();
    }
}
