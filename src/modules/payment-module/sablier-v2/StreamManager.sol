// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.22;

import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";
import { ISablierV2Lockup } from "@sablier/v2-core/src/interfaces/ISablierV2Lockup.sol";
import { LockupLinear, LockupTranched } from "@sablier/v2-core/src/types/DataTypes.sol";
import { Broker, LockupLinear } from "@sablier/v2-core/src/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ud60x18, UD60x18, ud, intoUint128 } from "@prb/math/src/UD60x18.sol";

import { IStreamManager } from "./interfaces/IStreamManager.sol";
import { Errors } from "./../libraries/Errors.sol";
import { Types } from "./../libraries/Types.sol";

/// @title StreamManager
/// @dev See the documentation in {IStreamManager}
abstract contract StreamManager is IStreamManager {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStreamManager
    ISablierV2LockupLinear public immutable override LOCKUP_LINEAR;

    /// @inheritdoc IStreamManager
    ISablierV2LockupTranched public immutable override LOCKUP_TRANCHED;

    /// @inheritdoc IStreamManager
    address public override brokerAdmin;

    /// @inheritdoc IStreamManager
    UD60x18 public override brokerFee;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Stores the initial address of the account that started the stream
    /// By default, each stream will be created by this contract (the sender address of each stream will be address(this))
    /// therefore this mapping is used to allow only authorized senders to execute management-related actions i.e. cancellations
    mapping(uint256 streamId => address initialSender) private _initialStreamSender;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the address of the {SablierV2LockupLinear} and {SablierV2LockupTranched} contracts
    /// and the address of the broker admin account or contract
    constructor(
        ISablierV2LockupLinear _sablierLockupLinear,
        ISablierV2LockupTranched _sablierLockupTranched,
        address _brokerAdmin
    ) {
        LOCKUP_LINEAR = _sablierLockupLinear;
        LOCKUP_TRANCHED = _sablierLockupTranched;
        brokerAdmin = _brokerAdmin;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStreamManager
    function getLinearStream(uint256 streamId) public view returns (LockupLinear.StreamLL memory stream) {
        stream = LOCKUP_LINEAR.getStream(streamId);
    }

    /// @inheritdoc IStreamManager
    function getTranchedStream(uint256 streamId) public view returns (LockupTranched.StreamLT memory stream) {
        stream = LOCKUP_TRANCHED.getStream(streamId);
    }

    /// @inheritdoc IStreamManager
    function withdrawableAmountOf(
        Types.Method streamType,
        uint256 streamId
    ) public view returns (uint128 withdrawableAmount) {
        withdrawableAmount = _getISablierV2Lockup(streamType).withdrawableAmountOf(streamId);
    }

    /// @inheritdoc IStreamManager
    function streamedAmountOf(Types.Method streamType, uint256 streamId) public view returns (uint128 streamedAmount) {
        streamedAmount = _getISablierV2Lockup(streamType).streamedAmountOf(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStreamManager
    function createLinearStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        uint40 endTime,
        address recipient
    ) public returns (uint256 streamId) {
        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier contract to spend it
        _transferFromAndApprove({ asset: asset, amount: totalAmount, spender: address(LOCKUP_LINEAR) });

        // Create the Lockup Linear stream
        streamId = _createLinearStream(asset, totalAmount, startTime, endTime, recipient);

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        _initialStreamSender[streamId] = msg.sender;
    }

    /// @inheritdoc IStreamManager
    function createTranchedStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        address recipient,
        uint128 numberOfTranches,
        Types.Recurrence recurrence
    ) public returns (uint256 streamId) {
        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier contract to spend it
        _transferFromAndApprove({ asset: asset, amount: totalAmount, spender: address(LOCKUP_TRANCHED) });

        // Create the Lockup Linear stream
        streamId = _createTranchedStream(asset, totalAmount, startTime, recipient, numberOfTranches, recurrence);

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        _initialStreamSender[streamId] = msg.sender;
    }

    /// @inheritdoc IStreamManager
    function updateStreamBrokerFee(UD60x18 newBrokerFee) public {
        // Checks: the `msg.sender` is the broker admin
        if (msg.sender != brokerAdmin) revert Errors.OnlyBrokerAdmin();

        // Log the broker fee update
        emit BrokerFeeUpdated({ oldFee: brokerFee, newFee: newBrokerFee });

        // Update the fee charged by the broker
        brokerFee = newBrokerFee;
    }

    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates a Lockup Linear stream
    /// See https://docs.sablier.com/concepts/protocol/stream-types#lockup-linear
    function _createLinearStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        uint40 endTime,
        address recipient
    ) internal returns (uint256 streamId) {
        // Declare the params struct
        LockupLinear.CreateWithTimestamps memory params;

        // Declare the function parameters
        params.sender = address(this); // The sender will be able to cancel the stream
        params.recipient = recipient; // The recipient of the streamed assets
        params.totalAmount = totalAmount; // Total amount is the amount inclusive of all fees
        params.asset = asset; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = true; // Whether the stream will be transferable or not
        params.timestamps = LockupLinear.Timestamps({ start: startTime, cliff: 0, end: endTime });
        params.broker = Broker({ account: brokerAdmin, fee: brokerFee }); // Optional parameter for charging a fee

        // Create the LockupLinear stream using a function that sets the start time to `block.timestamp`
        streamId = LOCKUP_LINEAR.createWithTimestamps(params);
    }

    /// @dev Creates a Lockup Tranched stream
    /// See https://docs.sablier.com/concepts/protocol/stream-types#unlock-monthly
    function _createTranchedStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        address recipient,
        uint128 numberOfTranches,
        Types.Recurrence recurrence
    ) internal returns (uint256 streamId) {
        // Declare the params struct
        LockupTranched.CreateWithTimestamps memory params;

        // Declare the function parameters
        params.sender = address(this); // The sender will be able to cancel the stream
        params.recipient = recipient; // The recipient of the streamed assets
        params.totalAmount = totalAmount; // Total amount is the amount inclusive of all fees
        params.asset = asset; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = true; // Whether the stream will be transferable or not
        params.startTime = startTime; // The timestamp when to start streaming

        // Calculate the duration of each tranche based on the payment recurrence
        uint40 durationPerTranche = _getDurationPerTrache(recurrence);

        // Calculate the broker fee amount
        uint128 brokerFeeAmount = ud(totalAmount).mul(brokerFee).intoUint128();

        // Calculate the remaining amount to be streamed after substracting the broker fee
        uint128 deposit = totalAmount - brokerFeeAmount;

        // Calculate the amount that must be unlocked with each tranche
        uint128 amountPerTranche = deposit / numberOfTranches;
        uint128 estimatedDepositAmount;

        // Create the tranches array
        params.tranches = new LockupTranched.Tranche[](numberOfTranches);
        for (uint256 i; i < numberOfTranches; ++i) {
            params.tranches[i] = LockupTranched.Tranche({
                amount: amountPerTranche,
                timestamp: startTime + durationPerTranche
            });

            // Jump to the next tranche by adding the duration per tranche timestamp to the start time
            startTime += durationPerTranche;

            // Sum the individual tranche amount to get the estimated deposit amount
            estimatedDepositAmount += params.tranches[i].amount;
        }

        // Account for rounding errors by adjusting the last tranche
        params.tranches[numberOfTranches - 1].amount += deposit - estimatedDepositAmount;

        // Optional parameter for charging a fee
        params.broker = Broker({ account: brokerAdmin, fee: brokerFee });

        // Create the LockupTranched stream
        streamId = LOCKUP_TRANCHED.createWithTimestamps(params);
    }

    /// @dev See the documentation in {ISablierV2Lockup-withdrawMax}
    /// Notes:
    /// - `streamType` parameter has been added to withdraw from the according {ISablierV2Lockup} contract
    function _withdrawStream(
        Types.Method streamType,
        uint256 streamId,
        address to
    ) internal returns (uint128 withdrawnAmount) {
        // Set the according {ISablierV2Lockup} based on the stream type
        ISablierV2Lockup sablier = _getISablierV2Lockup(streamType);

        // Withdraw the maximum withdrawable amount
        return sablier.withdrawMax(streamId, to);
    }

    /// @dev Withdraws the maximum withdrawable amount and transfers the stream NFT to the new recipient
    /// Notes:
    /// - `streamType` parameter has been added to withdraw from the according {ISablierV2Lockup} contract
    function _withdrawMaxAndTransferStream(
        Types.Method streamType,
        uint256 streamId,
        address newRecipient
    ) internal returns (uint128 withdrawnAmount) {
        // Set the according {ISablierV2Lockup} based on the stream type
        ISablierV2Lockup sablier = _getISablierV2Lockup(streamType);

        // Checks: the caller is the current recipient. This also checks that the NFT was not burned.
        address currentRecipient = sablier.ownerOf(streamId);

        // Checks, Effects and Interactions: withdraw the maximum withdrawable amount
        withdrawnAmount = sablier.withdrawMax(streamId, currentRecipient);

        // Interactions: transfer the stream to the new recipient
        sablier.transferFrom({ from: msg.sender, to: newRecipient, tokenId: streamId });
    }

    /// @dev See the documentation in {ISablierV2Lockup-cancel}
    ///
    /// Notes:
    /// - `msg.sender` must be the initial stream creator
    function _cancelStream(Types.Method streamType, uint256 streamId) internal {
        // Set the according {ISablierV2Lockup} based on the stream type
        ISablierV2Lockup sablier = _getISablierV2Lockup(streamType);

        // Checks: the `msg.sender` is the initial stream creator
        address initialSender = _initialStreamSender[streamId];
        if (msg.sender != initialSender) revert Errors.OnlyInitialStreamSender(initialSender);

        // Checks, Effect, Interactions: cancel the stream
        sablier.cancel(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OTHER INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Transfers the `amount` of `asset` tokens to this address (or the contract inherting from)
    /// and approves either the `SablierV2LockupLinear` or `SablierV2LockupTranched` to spend the amount
    function _transferFromAndApprove(IERC20 asset, uint128 amount, address spender) internal {
        // Transfer the provided amount of ERC-20 tokens to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve the Sablier contract to spend the ERC-20 tokens
        asset.approve(spender, amount);
    }

    /// @dev Retrieves the duration of each tranche from a tranched stream based on a recurrence
    function _getDurationPerTrache(Types.Recurrence recurrence) internal pure returns (uint40 duration) {
        if (recurrence == Types.Recurrence.Weekly) duration = 1 weeks;
        else if (recurrence == Types.Recurrence.Monthly) duration = 4 weeks;
        else if (recurrence == Types.Recurrence.Yearly) duration = 48 weeks;
    }

    /// @dev Retrieves the according {ISablierV2Lockup} contract based on the stream type
    function _getISablierV2Lockup(Types.Method streamType) internal view returns (ISablierV2Lockup sablier) {
        if (streamType == Types.Method.LinearStream) {
            sablier = LOCKUP_LINEAR;
        } else {
            sablier = LOCKUP_TRANCHED;
        }
    }
}
