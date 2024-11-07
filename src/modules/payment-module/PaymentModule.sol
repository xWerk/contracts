// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

import { Types } from "./libraries/Types.sol";
import { Errors } from "./libraries/Errors.sol";
import { IPaymentModule } from "./interfaces/IPaymentModule.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { StreamManager } from "./sablier-v2/StreamManager.sol";
import { Helpers } from "./libraries/Helpers.sol";

/// @title PaymentModule
/// @notice See the documentation in {IPaymentModule}
contract PaymentModule is IPaymentModule, StreamManager {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Payment requests details mapped by the `id` payment request ID
    mapping(uint256 id => Types.PaymentRequest) private _requests;

    /// @dev Counter to keep track of the next ID used to create a new payment request
    uint256 private _nextRequestId;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {StreamManager} contract and first request  ID
    constructor(
        ISablierV2LockupLinear _sablierLockupLinear,
        ISablierV2LockupTranched _sablierLockupTranched,
        address _brokerAdmin
    ) StreamManager(_sablierLockupLinear, _sablierLockupTranched, _brokerAdmin) {
        // Start the first payment request ID from 1
        _nextRequestId = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        // Checks: the sender is a valid non-zero code size contract
        if (msg.sender.code.length == 0) {
            revert Errors.SpaceZeroCodeSize();
        }

        // Checks: the sender implements the ERC-165 interface required by {ISpace}
        bytes4 interfaceId = type(ISpace).interfaceId;
        if (!ISpace(msg.sender).supportsInterface(interfaceId)) revert Errors.SpaceUnsupportedInterface();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentModule
    function getRequest(uint256 id) external view returns (Types.PaymentRequest memory request) {
        return _requests[id];
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymentModule
    function createRequest(Types.PaymentRequest calldata request) external onlySpace returns (uint256 id) {
        // Checks: the amount is non-zero
        if (request.config.amount == 0) {
            revert Errors.ZeroPaymentAmount();
        }

        // Checks: the start time is stricly lower than the end time
        if (request.startTime > request.endTime) {
            revert Errors.StartTimeGreaterThanEndTime();
        }

        // Checks: end time is not in the past
        uint40 currentTime = uint40(block.timestamp);
        if (currentTime >= request.endTime) {
            revert Errors.EndTimeInThePast();
        }

        // Checks: the recurrence type is not equal to one-off if dealing with a tranched stream-based request
        if (request.config.method == Types.Method.TranchedStream) {
            // The recurrence cannot be set to one-off
            if (request.config.recurrence == Types.Recurrence.OneOff) {
                revert Errors.TranchedStreamInvalidOneOffRecurence();
            }
        }

        // Validates the payment request interval (endTime - startTime) and returns the number of payments
        // based on the payment method, interval and recurrence type
        //
        // Notes:
        // - The number of payments is taken into account only for transfer-based invoices
        // - There should be only one payment when dealing with a one-off transfer-based request
        // - When dealing with a recurring transfer, the number of payments must be calculated based
        // on the payment interval (endTime - startTime) and recurrence type
        uint40 numberOfPayments;
        if (request.config.method == Types.Method.Transfer && request.config.recurrence == Types.Recurrence.OneOff) {
            numberOfPayments = 1;
        } else if (request.config.method != Types.Method.LinearStream) {
            numberOfPayments = _checkIntervalPayments({
                recurrence: request.config.recurrence,
                startTime: request.startTime,
                endTime: request.endTime
            });

            // Set the number of payments to zero if dealing with a tranched-based request
            // The `_checkIntervalPayment` method is still called for a tranched-based request  just
            // to validate the interval and ensure it can support multiple payments based on the chosen recurrence
            if (request.config.method == Types.Method.TranchedStream) numberOfPayments = 0;
        }

        // Checks: the asset is different than the native token if dealing with either a linear or tranched stream-based payment
        if (request.config.method != Types.Method.Transfer) {
            if (request.config.asset == address(0)) {
                revert Errors.OnlyERC20StreamsAllowed();
            }
        }

        // Get the next payment request ID
        id = _nextRequestId;

        // Effects: create the payment request
        _requests[id] = Types.PaymentRequest({
            status: Types.Status.Pending,
            startTime: request.startTime,
            endTime: request.endTime,
            recipient: request.recipient,
            config: Types.Config({
                recurrence: request.config.recurrence,
                method: request.config.method,
                paymentsLeft: numberOfPayments,
                amount: request.config.amount,
                asset: request.config.asset,
                streamId: 0
            })
        });

        // Effects: increment the next payment request ID
        // Use unchecked because the request  id cannot realistically overflow
        unchecked {
            ++_nextRequestId;
        }

        // Log the payment request creation
        emit RequestCreated({
            id: id,
            recipient: msg.sender,
            startTime: request.startTime,
            endTime: request.endTime,
            config: request.config
        });
    }

    /// @inheritdoc IPaymentModule
    function payRequest(uint256 id) external payable {
        // Load the payment request state from storage
        Types.PaymentRequest memory request = _requests[id];

        // Checks: the payment request is not already completed or canceled
        if (request.status == Types.Status.Completed) {
            revert Errors.RequestCompleted();
        } else if (request.status == Types.Status.Canceled) {
            revert Errors.RequestCanceled();
        }

        // Handle the payment workflow depending on the payment method type
        if (request.config.method == Types.Method.Transfer) {
            // Effects: pay the request  and update its status to `Completed` or `Accepted` depending on the payment type
            _payByTransfer(id, request);
        } else {
            uint256 streamId;
            // Check to see whether the request  must be paid through a linear or tranched stream
            if (request.config.method == Types.Method.LinearStream) {
                streamId = _payByLinearStream(request);
            } else {
                streamId = _payByTranchedStream(request);
            }

            // Effects: update the status of the request  to `Accepted` and the stream ID
            // if dealing with a linear or tranched-based request
            _requests[id].status = Types.Status.Accepted;
            _requests[id].config.streamId = streamId;
        }

        // Log the payment transaction
        emit RequestPaid({ id: id, payer: msg.sender, status: _requests[id].status, config: _requests[id].config });
    }

    /// @inheritdoc IPaymentModule
    function cancelRequest(uint256 id) external {
        // Load the payment request state from storage
        Types.PaymentRequest memory request = _requests[id];

        // Checks: the payment request is already completed
        if (request.status == Types.Status.Completed) {
            revert Errors.RequestCompleted();
        } else if (request.status == Types.Status.Canceled) {
            revert Errors.RequestCanceled();
        }

        // Checks: `msg.sender` is the recipient if the payment request status is pending
        //
        // Notes:
        // - Once a linear or tranched stream is created, the `msg.sender` is checked in the
        // {SablierV2Lockup} `cancel` method
        if (request.status == Types.Status.Pending) {
            if (request.recipient != msg.sender) {
                revert Errors.OnlyRequestRecipient();
            }
        }
        // Checks, Effects, Interactions: cancel the stream if payment request has already been accepted
        // and the payment method is either linear or tranched stream
        //
        // Notes:
        // - A transfer-based payment request can be canceled directly
        // - A linear or tranched stream MUST be canceled by calling the `cancel` method on the according
        // {ISablierV2Lockup} contract
        else if (request.status == Types.Status.Accepted && request.config.method != Types.Method.Transfer) {
            _cancelStream({ streamType: request.config.method, streamId: request.config.streamId });
        }

        // Effects: mark the payment request as canceled
        _requests[id].status = Types.Status.Canceled;

        // Log the payment request cancelation
        emit RequestCanceled(id);
    }

    /// @inheritdoc IPaymentModule
    function withdrawRequestStream(uint256 id) public returns (uint128 withdrawnAmount) {
        // Load the payment request state from storage
        Types.PaymentRequest memory request = _requests[id];

        // Retrieve the recipient of the request
        address recipient = request.recipient;

        // Effects: update the request  status to `Completed` once the full payment amount has been successfully streamed
        uint128 streamedAmount = streamedAmountOf({
            streamType: request.config.method,
            streamId: request.config.streamId
        });
        if (streamedAmount == request.config.amount) {
            _requests[id].status = Types.Status.Completed;
        }

        // Check, Effects, Interactions: withdraw from the stream
        return _withdrawStream({ streamType: request.config.method, streamId: request.config.streamId, to: recipient });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    INTERNAL-METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Pays the `id` request  by transfer
    function _payByTransfer(uint256 id, Types.PaymentRequest memory request) internal {
        // Effects: update the request  status to `Completed` if the required number of payments has been made
        // Using unchecked because the number of payments left cannot underflow as the request  status
        // will be updated to `Completed` once `paymentLeft` is zero
        unchecked {
            uint40 paymentsLeft = request.config.paymentsLeft - 1;
            _requests[id].config.paymentsLeft = paymentsLeft;
            if (paymentsLeft == 0) {
                _requests[id].status = Types.Status.Completed;
            } else if (request.status == Types.Status.Pending) {
                _requests[id].status = Types.Status.Accepted;
            }
        }

        // Check if the payment must be done in native token (ETH) or an ERC-20 token
        if (request.config.asset == address(0)) {
            // Checks: the payment amount matches the request  value
            if (msg.value < request.config.amount) {
                revert Errors.PaymentAmountLessThanInvoiceValue({ amount: request.config.amount });
            }

            // Interactions: pay the recipient with native token (ETH)
            (bool success, ) = payable(request.recipient).call{ value: request.config.amount }("");
            if (!success) revert Errors.NativeTokenPaymentFailed();
        } else {
            // Interactions: pay the recipient with the ERC-20 token
            IERC20(request.config.asset).safeTransferFrom({
                from: msg.sender,
                to: request.recipient,
                value: request.config.amount
            });
        }
    }

    /// @dev Create the linear stream payment
    function _payByLinearStream(Types.PaymentRequest memory request) internal returns (uint256 streamId) {
        streamId = StreamManager.createLinearStream({
            asset: IERC20(request.config.asset),
            totalAmount: request.config.amount,
            startTime: request.startTime,
            endTime: request.endTime,
            recipient: request.recipient
        });
    }

    /// @dev Create the tranched stream payment
    function _payByTranchedStream(Types.PaymentRequest memory request) internal returns (uint256 streamId) {
        uint40 numberOfTranches = Helpers.computeNumberOfPayments(
            request.config.recurrence,
            request.endTime - request.startTime
        );

        streamId = StreamManager.createTranchedStream({
            asset: IERC20(request.config.asset),
            totalAmount: request.config.amount,
            startTime: request.startTime,
            recipient: request.recipient,
            numberOfTranches: numberOfTranches,
            recurrence: request.config.recurrence
        });
    }

    /// @notice Calculates the number of payments to be made for a recurring transfer and tranched stream-based request
    /// @dev Reverts if the number of payments is zero, indicating that either the interval or recurrence type was set incorrectly
    function _checkIntervalPayments(
        Types.Recurrence recurrence,
        uint40 startTime,
        uint40 endTime
    ) internal pure returns (uint40 numberOfPayments) {
        // Checks: the request  payment interval matches the recurrence type
        // This cannot underflow as the start time is stricly lower than the end time when this call executes
        uint40 interval;
        unchecked {
            interval = endTime - startTime;
        }

        // Check and calculate the expected number of payments based on the request  recurrence and payment interval
        numberOfPayments = Helpers.computeNumberOfPayments(recurrence, interval);

        // Revert if there are zero payments to be made since the payment method due to invalid interval and recurrence type
        if (numberOfPayments == 0) {
            revert Errors.PaymentIntervalTooShortForSelectedRecurrence();
        }
    }
}
