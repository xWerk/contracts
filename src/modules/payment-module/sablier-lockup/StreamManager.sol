// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.22;

import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { Broker, Lockup, LockupLinear, LockupTranched } from "@sablier/lockup/src/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ud60x18, UD60x18, ud, intoUint128 } from "@prb/math/src/UD60x18.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IStreamManager } from "./interfaces/IStreamManager.sol";
import { Errors } from "./../libraries/Errors.sol";
import { Types } from "./../libraries/Types.sol";

/// @title StreamManager
/// @dev See the documentation in {IStreamManager}
abstract contract StreamManager is IStreamManager, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.StreamManager
    struct StreamManagerStorage {
        /// @notice The Sablier Lockup contract address
        ISablierLockup SABLIER_LOCKUP;
        /// @notice Stores the initial address of the account that started the stream
        /// By default, each stream will be created by this contract (the sender address of each stream will be address(this))
        /// therefore this mapping is used to allow only authorized senders to execute management-related actions i.e. cancellations
        mapping(uint256 streamId => address initialSender) initialStreamSender;
        /// @notice The broker parameters charged to create Sablier Lockup stream
        Broker broker;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.StreamManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STREAM_MANAGER_STORAGE_LOCATION =
        0x37eb5ed31cc419f1937b308ec5ab43829484edc140a0a162efda74d20d290400;

    /// @dev Retrieves the storage of the {StreamManager} contract
    function _getStreamManagerStorage() internal pure returns (StreamManagerStorage storage $) {
        assembly {
            $.slot := STREAM_MANAGER_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __StreamManager_init(
        ISablierLockup _sablierLockup,
        address _initialAdmin,
        address _brokerAccount,
        UD60x18 _brokerFee
    )
        internal
        onlyInitializing
    {
        __Ownable_init(_initialAdmin);

        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Set the {SablierLockup} contract address
        $.SABLIER_LOCKUP = _sablierLockup;

        // Set the broker account and fee
        $.broker = Broker({ account: _brokerAccount, fee: _brokerFee });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStreamManager
    function SABLIER_LOCKUP() public view returns (ISablierLockup sablierLockup) {
        return _getStreamManagerStorage().SABLIER_LOCKUP;
    }

    /// @inheritdoc IStreamManager
    function broker() public view returns (Broker memory brokerConfig) {
        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Return the broker fee
        brokerConfig = $.broker;
    }

    /// @inheritdoc IStreamManager
    function getDepositedAmount(uint256 streamId) public view returns (uint128 depositedAmount) {
        depositedAmount = SABLIER_LOCKUP().getDepositedAmount(streamId);
    }

    /// @inheritdoc IStreamManager
    function getRecipient(uint256 streamId) public view returns (address recipient) {
        recipient = SABLIER_LOCKUP().getRecipient(streamId);
    }

    /// @inheritdoc IStreamManager
    function getSender(uint256 streamId) public view returns (address sender) {
        sender = SABLIER_LOCKUP().getSender(streamId);
    }

    /// @inheritdoc IStreamManager
    function getRefundedAmount(uint256 streamId) public view returns (uint128 refundedAmount) {
        refundedAmount = SABLIER_LOCKUP().getRefundedAmount(streamId);
    }

    /// @inheritdoc IStreamManager
    function getStartTime(uint256 streamId) public view returns (uint40 startTime) {
        startTime = SABLIER_LOCKUP().getStartTime(streamId);
    }

    /// @inheritdoc IStreamManager
    function getEndTime(uint256 streamId) public view returns (uint40 endTime) {
        endTime = SABLIER_LOCKUP().getEndTime(streamId);
    }

    /// @inheritdoc IStreamManager
    function getUnderlyingToken(uint256 streamId) public view returns (IERC20 underlyingToken) {
        underlyingToken = SABLIER_LOCKUP().getUnderlyingToken(streamId);
    }

    /// @inheritdoc IStreamManager
    function withdrawableAmountOf(uint256 streamId) public view returns (uint128 withdrawableAmount) {
        withdrawableAmount = SABLIER_LOCKUP().withdrawableAmountOf(streamId);
    }

    /// @inheritdoc IStreamManager
    function streamedAmountOf(uint256 streamId) public view returns (uint128 streamedAmount) {
        streamedAmount = SABLIER_LOCKUP().streamedAmountOf(streamId);
    }

    /// @inheritdoc IStreamManager
    function statusOfStream(uint256 streamId) public view returns (Lockup.Status status) {
        status = SABLIER_LOCKUP().statusOf(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStreamManager
    function updateStreamBrokerFee(UD60x18 newBrokerFee) public onlyOwner {
        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Log the broker fee update
        emit BrokerFeeUpdated({ oldFee: $.broker.fee, newFee: newBrokerFee });

        // Update the fee charged by the broker
        $.broker.fee = newBrokerFee;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SABLIER LOCKUP INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates a Lockup Linear streams
    /// See https://docs.sablier.com/concepts/protocol/stream-types#lockup-linear
    ///
    /// @param asset The address of the ERC-20 token to be streamed
    /// @param totalAmount The total amount of ERC-20 tokens to be streamed
    /// @param startTime The timestamp when the stream takes effect
    /// @param endTime The timestamp by which the stream must be paid
    /// @param recipient The address receiving the ERC-20 tokens
    function _createLinearStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        uint40 endTime,
        address recipient
    )
        internal
        returns (uint256 streamId)
    {
        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier contract to spend it
        _transferFromAndApprove({ asset: asset, amount: totalAmount, spender: address($.SABLIER_LOCKUP) });

        // Declare the params struct
        Lockup.CreateWithTimestamps memory params;

        // Declare the function parameters
        params.sender = address(this); // The sender will be able to cancel the stream
        params.recipient = recipient; // The recipient of the streamed assets
        params.totalAmount = totalAmount; // Total amount is the amount inclusive of all fees
        params.token = asset; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = false; // Whether the stream will be transferable or not
        params.timestamps = Lockup.Timestamps({ start: startTime, end: endTime });
        params.broker = Broker({ account: $.broker.account, fee: $.broker.fee }); // Optional parameter for charging a fee

        // Declare the unlock amounts
        LockupLinear.UnlockAmounts memory unlockAmounts = LockupLinear.UnlockAmounts({ start: 0, cliff: 0 });

        // Create the Lockup Linear stream
        streamId =
            $.SABLIER_LOCKUP.createWithTimestampsLL({ params: params, unlockAmounts: unlockAmounts, cliffTime: 0 });

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        $.initialStreamSender[streamId] = msg.sender;
    }

    /// @dev Creates a Lockup Tranched stream
    /// See https://docs.sablier.com/concepts/protocol/stream-types#unlock-monthly
    ///
    /// @param asset The address of the ERC-20 token to be streamed
    /// @param totalAmount The total amount of ERC-20 tokens to be streamed
    /// @param startTime The timestamp when the stream takes effect
    /// @param recipient The address receiving the ERC-20 tokens
    /// @param numberOfTranches The number of tranches paid by the stream
    /// @param recurrence The recurrence of each tranche
    function _createTranchedStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        address recipient,
        uint128 numberOfTranches,
        Types.Recurrence recurrence
    )
        internal
        returns (uint256 streamId)
    {
        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier contract to spend it
        _transferFromAndApprove({ asset: asset, amount: totalAmount, spender: address($.SABLIER_LOCKUP) });

        // Calculate the broker fee amount
        uint128 brokerFeeAmount = ud(totalAmount).mul($.broker.fee).intoUint128();

        // Calculate the remaining amount to be streamed after subtracting the broker fee
        uint128 deposit = totalAmount - brokerFeeAmount;

        // Declare the params struct
        Lockup.CreateWithTimestamps memory params;

        // Create the tranches array
        LockupTranched.Tranche[] memory tranches = _createTranches(startTime, deposit, numberOfTranches, recurrence);

        // Populate the stream parameters
        params.sender = address(this); // The sender will be able to cancel the stream
        params.recipient = recipient; // The recipient of the streamed assets
        params.totalAmount = totalAmount; // Total amount is the amount inclusive of all fees
        params.token = asset; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = false; // Whether the stream will be transferable or not
        params.timestamps = Lockup.Timestamps({ start: startTime, end: tranches[tranches.length - 1].timestamp });

        // Optional parameter for charging a fee
        params.broker = Broker({ account: $.broker.account, fee: $.broker.fee });

        // Create the LockupTranched stream
        streamId = $.SABLIER_LOCKUP.createWithTimestampsLT(params, tranches);

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        $.initialStreamSender[streamId] = msg.sender;
    }

    /// @dev Creates the tranches array for a Lockup Tranched stream
    function _createTranches(
        uint40 startTime,
        uint128 deposit,
        uint128 numberOfTranches,
        Types.Recurrence recurrence
    )
        internal
        pure
        returns (LockupTranched.Tranche[] memory)
    {
        // Calculate the duration of each tranche based on the payment recurrence
        uint40 durationPerTranche = _getDurationPerTranche(recurrence);

        // Calculate the amount that must be unlocked with each tranche
        uint128 amountPerTranche = deposit / numberOfTranches;
        uint128 estimatedDepositAmount;

        // Create the tranches array
        LockupTranched.Tranche[] memory tranches = new LockupTranched.Tranche[](numberOfTranches);
        uint40 lastEndTimestamp = startTime;

        for (uint256 i; i < numberOfTranches; ++i) {
            // Calculate the end timestamp of the current tranche
            lastEndTimestamp += durationPerTranche;

            // Create the tranche by specifying the amount and the end timestamp
            tranches[i] = LockupTranched.Tranche({ amount: amountPerTranche, timestamp: lastEndTimestamp });

            // Sum up the individual tranche amount to get the estimated deposit amount
            estimatedDepositAmount += amountPerTranche;
        }

        // Account for rounding errors by adjusting the last tranche
        tranches[numberOfTranches - 1].amount += deposit - estimatedDepositAmount;

        return tranches;
    }

    /// @dev See the documentation in {ISablierV2Lockup-withdrawMax}
    ///
    /// Notes:
    /// - `streamType` parameter has been added to withdraw from the according {ISablierV2Lockup} contract
    function _withdrawStream(uint256 streamId, address to) internal returns (uint128 withdrawnAmount) {
        // Withdraw the maximum withdrawable amount
        return SABLIER_LOCKUP().withdrawMax(streamId, to);
    }

    /// @dev See the documentation in {ISablierV2Lockup-cancel}
    ///
    /// Notes:
    /// - `msg.sender` must be the initial stream creator
    function _cancelStream(uint256 streamId) internal {
        // Retrieve the storage of the {StreamManager} contract
        StreamManagerStorage storage $ = _getStreamManagerStorage();

        // Checks: the `msg.sender` is the initial stream creator
        address initialSender = $.initialStreamSender[streamId];
        if (msg.sender != initialSender) revert Errors.OnlyInitialStreamSender(initialSender);

        // Checks, Effect, Interactions: cancel the stream
        SABLIER_LOCKUP().cancel(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OTHER INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Transfers the `amount` of `asset` tokens to this address (or the contract inheriting from)
    /// and approves either the `SablierV2LockupLinear` or `SablierV2LockupTranched` to spend the amount
    function _transferFromAndApprove(IERC20 asset, uint128 amount, address spender) internal {
        // Transfer the provided amount of ERC-20 tokens to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve the Sablier contract to spend the ERC-20 tokens
        asset.approve(spender, amount);
    }

    /// @dev Retrieves the duration of each tranche from a tranched stream based on a recurrence
    function _getDurationPerTranche(Types.Recurrence recurrence) internal pure returns (uint40 duration) {
        if (recurrence == Types.Recurrence.Weekly) duration = 1 weeks;
        else if (recurrence == Types.Recurrence.Monthly) duration = 4 weeks;
        else if (recurrence == Types.Recurrence.Yearly) duration = 48 weeks;
    }
}
