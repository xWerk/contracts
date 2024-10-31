// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

import { Types } from "./libraries/Types.sol";
import { Errors } from "./libraries/Errors.sol";
import { IInvoiceModule } from "./interfaces/IInvoiceModule.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { StreamManager } from "./sablier-v2/StreamManager.sol";
import { Helpers } from "./libraries/Helpers.sol";

/// @title InvoiceModule
/// @notice See the documentation in {IInvoiceModule}
contract InvoiceModule is IInvoiceModule, StreamManager, ERC721 {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Invoice details mapped by the `id` invoice ID
    mapping(uint256 id => Types.Invoice) private _invoices;

    /// @dev Counter to keep track of the next ID used to create a new invoice
    uint256 private _nextInvoiceId;

    /// @dev Base URI used to get the ERC-721 `tokenURI` metadata JSON schema
    string private _collectionURI;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {StreamManager} contract and first invoice ID
    constructor(
        ISablierV2LockupLinear _sablierLockupLinear,
        ISablierV2LockupTranched _sablierLockupTranched,
        address _brokerAdmin,
        string memory _URI
    )
        StreamManager(_sablierLockupLinear, _sablierLockupTranched, _brokerAdmin)
        ERC721("Metastation Invoice NFT", "MD-INVOICES")
    {
        // Start the invoice IDs from 1
        _nextInvoiceId = 1;

        // Set the ERC721 baseURI
        _collectionURI = _URI;
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

    /// @inheritdoc IInvoiceModule
    function getInvoice(uint256 id) external view returns (Types.Invoice memory invoice) {
        return _invoices[id];
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInvoiceModule
    function createInvoice(Types.Invoice calldata invoice) external onlySpace returns (uint256 invoiceId) {
        // Checks: the amount is non-zero
        if (invoice.payment.amount == 0) {
            revert Errors.ZeroPaymentAmount();
        }

        // Checks: the start time is stricly lower than the end time
        if (invoice.startTime > invoice.endTime) {
            revert Errors.StartTimeGreaterThanEndTime();
        }

        // Checks: end time is not in the past
        uint40 currentTime = uint40(block.timestamp);
        if (currentTime >= invoice.endTime) {
            revert Errors.EndTimeInThePast();
        }

        // Checks: the recurrence type is not equal to one-off if dealing with a tranched stream-based invoice
        if (invoice.payment.method == Types.Method.TranchedStream) {
            // The recurrence cannot be set to one-off
            if (invoice.payment.recurrence == Types.Recurrence.OneOff) {
                revert Errors.TranchedStreamInvalidOneOffRecurence();
            }
        }

        // Validates the invoice interval (endTime - startTime) and returns the number of payments of the invoice
        // based on the payment method, interval and recurrence type
        //
        // Notes:
        // - The number of payments is taken into account only for transfer-based invoices
        // - There should be only one payment when dealing with a one-off transfer-based invoice
        // - When dealing with a recurring transfer, the number of payments must be calculated based
        // on the payment interval (endTime - startTime) and recurrence type
        uint40 numberOfPayments;
        if (invoice.payment.method == Types.Method.Transfer && invoice.payment.recurrence == Types.Recurrence.OneOff) {
            numberOfPayments = 1;
        } else if (invoice.payment.method != Types.Method.LinearStream) {
            numberOfPayments = _checkIntervalPayments({
                recurrence: invoice.payment.recurrence,
                startTime: invoice.startTime,
                endTime: invoice.endTime
            });

            // Set the number of payments to zero if dealing with a tranched-based invoice
            // The `_checkIntervalPayment` method is still called for a tranched-based invoice just
            // to validate the interval and ensure it can support multiple payments based on the chosen recurrence
            if (invoice.payment.method == Types.Method.TranchedStream) numberOfPayments = 0;
        }

        // Checks: the asset is different than the native token if dealing with either a linear or tranched stream-based invoice
        if (invoice.payment.method != Types.Method.Transfer) {
            if (invoice.payment.asset == address(0)) {
                revert Errors.OnlyERC20StreamsAllowed();
            }
        }

        // Get the next invoice ID
        invoiceId = _nextInvoiceId;

        // Effects: create the invoice
        _invoices[invoiceId] = Types.Invoice({
            status: Types.Status.Pending,
            startTime: invoice.startTime,
            endTime: invoice.endTime,
            payment: Types.Payment({
                recurrence: invoice.payment.recurrence,
                method: invoice.payment.method,
                paymentsLeft: numberOfPayments,
                amount: invoice.payment.amount,
                asset: invoice.payment.asset,
                streamId: 0
            })
        });

        // Effects: increment the next invoice id
        // Use unchecked because the invoice id cannot realistically overflow
        unchecked {
            ++_nextInvoiceId;
        }

        // Effects: mint the invoice NFT to the recipient space
        _mint({ to: msg.sender, tokenId: invoiceId });

        // Log the invoice creation
        emit InvoiceCreated({
            id: invoiceId,
            recipient: msg.sender,
            status: Types.Status.Pending,
            startTime: invoice.startTime,
            endTime: invoice.endTime,
            payment: invoice.payment
        });
    }

    /// @inheritdoc IInvoiceModule
    function payInvoice(uint256 id) external payable {
        // Load the invoice from storage
        Types.Invoice memory invoice = _invoices[id];

        // Retrieve the recipient of the invoice
        // This will also check if the invoice is minted or not burned
        address recipient = ownerOf(id);

        // Checks: the invoice is not already paid or canceled
        if (invoice.status == Types.Status.Paid) {
            revert Errors.InvoiceAlreadyPaid();
        } else if (invoice.status == Types.Status.Canceled) {
            revert Errors.InvoiceCanceled();
        }

        // Handle the payment workflow depending on the payment method type
        if (invoice.payment.method == Types.Method.Transfer) {
            // Effects: pay the invoice and update its status to `Paid` or `Ongoing` depending on the payment type
            _payByTransfer(id, invoice, recipient);
        } else {
            uint256 streamId;
            // Check to see whether the invoice must be paid through a linear or tranched stream
            if (invoice.payment.method == Types.Method.LinearStream) {
                streamId = _payByLinearStream(invoice, recipient);
            } else {
                streamId = _payByTranchedStream(invoice, recipient);
            }

            // Effects: update the status of the invoice to `Ongoing` and the stream ID
            // if dealing with a linear or tranched-based invoice
            _invoices[id].status = Types.Status.Ongoing;
            _invoices[id].payment.streamId = streamId;
        }

        // Log the payment transaction
        emit InvoicePaid({ id: id, payer: msg.sender, status: _invoices[id].status, payment: _invoices[id].payment });
    }

    /// @inheritdoc IInvoiceModule
    function cancelInvoice(uint256 id) external {
        // Load the invoice from storage
        Types.Invoice memory invoice = _invoices[id];

        // Checks: the invoice is paid or already canceled
        if (invoice.status == Types.Status.Paid) {
            revert Errors.CannotCancelPaidInvoice();
        } else if (invoice.status == Types.Status.Canceled) {
            revert Errors.InvoiceAlreadyCanceled();
        }

        // Checks: `msg.sender` is the recipient if invoice status is pending
        //
        // Notes:
        // - Once a linear or tranched stream is created, the `msg.sender` is checked in the
        // {SablierV2Lockup} `cancel` method
        if (invoice.status == Types.Status.Pending) {
            // Retrieve the recipient of the invoice
            address recipient = ownerOf(id);

            if (recipient != msg.sender) {
                revert Errors.OnlyInvoiceRecipient();
            }
        }
        // Checks, Effects, Interactions: cancel the stream if status is ongoing
        //
        // Notes:
        // - A transfer-based invoice can be canceled directly
        // - A linear or tranched stream MUST be canceled by calling the `cancel` method on the according
        // {ISablierV2Lockup} contract
        else if (invoice.status == Types.Status.Ongoing) {
            _cancelStream({ streamType: invoice.payment.method, streamId: invoice.payment.streamId });
        }

        // Effects: mark the invoice as canceled
        _invoices[id].status = Types.Status.Canceled;

        // Log the invoice cancelation
        emit InvoiceCanceled(id);
    }

    /// @inheritdoc IInvoiceModule
    function withdrawInvoiceStream(uint256 id) public returns (uint128 withdrawnAmount) {
        // Load the invoice from storage
        Types.Invoice memory invoice = _invoices[id];

        // Retrieve the recipient of the invoice
        address recipient = ownerOf(id);

        // Effects: update the invoice status to `Paid` once the full payment amount has been successfully streamed
        uint128 streamedAmount =
            streamedAmountOf({ streamType: invoice.payment.method, streamId: invoice.payment.streamId });
        if (streamedAmount == invoice.payment.amount) {
            _invoices[id].status = Types.Status.Paid;
        }

        // Check, Effects, Interactions: withdraw from the stream
        return
            _withdrawStream({ streamType: invoice.payment.method, streamId: invoice.payment.streamId, to: recipient });
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Checks: the `tokenId` was minted or is not burned
        _requireOwned(tokenId);

        // Create the `tokenURI` by concatenating the `baseURI`, `tokenId` and metadata extension (.json)
        string memory baseURI = _baseURI();
        return string.concat(baseURI, tokenId.toString(), ".json");
    }

    /// @inheritdoc ERC721
    function transferFrom(address from, address to, uint256 tokenId) public override {
        // Retrieve the invoice details
        Types.Invoice memory invoice = _invoices[tokenId];

        // Checks: the payment request has been accepted and a stream has already been
        // created if dealing with a stream-based payment
        if (invoice.payment.streamId != 0) {
            // Checks and Effects: withdraw the maximum withdrawable amount to the current stream recipient
            // and transfer the stream NFT to the new recipient
            _withdrawMaxAndTransferStream({
                streamType: invoice.payment.method,
                streamId: invoice.payment.streamId,
                newRecipient: to
            });
        }

        // Checks, Effects and Interactions: transfer the invoice NFT
        super.transferFrom(from, to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    INTERNAL-METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Pays the `id` invoice by transfer
    function _payByTransfer(uint256 id, Types.Invoice memory invoice, address recipient) internal {
        // Effects: update the invoice status to `Paid` if the required number of payments has been made
        // Using unchecked because the number of payments left cannot underflow as the invoice status
        // will be updated to `Paid` once `paymentLeft` is zero
        unchecked {
            uint40 paymentsLeft = invoice.payment.paymentsLeft - 1;
            _invoices[id].payment.paymentsLeft = paymentsLeft;
            if (paymentsLeft == 0) {
                _invoices[id].status = Types.Status.Paid;
            } else if (invoice.status == Types.Status.Pending) {
                _invoices[id].status = Types.Status.Ongoing;
            }
        }

        // Check if the payment must be done in native token (ETH) or an ERC-20 token
        if (invoice.payment.asset == address(0)) {
            // Checks: the payment amount matches the invoice value
            if (msg.value < invoice.payment.amount) {
                revert Errors.PaymentAmountLessThanInvoiceValue({ amount: invoice.payment.amount });
            }

            // Interactions: pay the recipient with native token (ETH)
            (bool success,) = payable(recipient).call{ value: invoice.payment.amount }("");
            if (!success) revert Errors.NativeTokenPaymentFailed();
        } else {
            // Interactions: pay the recipient with the ERC-20 token
            IERC20(invoice.payment.asset).safeTransferFrom({
                from: msg.sender,
                to: recipient,
                value: invoice.payment.amount
            });
        }
    }

    /// @dev Create the linear stream payment
    function _payByLinearStream(Types.Invoice memory invoice, address recipient) internal returns (uint256 streamId) {
        streamId = StreamManager.createLinearStream({
            asset: IERC20(invoice.payment.asset),
            totalAmount: invoice.payment.amount,
            startTime: invoice.startTime,
            endTime: invoice.endTime,
            recipient: recipient
        });
    }

    /// @dev Create the tranched stream payment
    function _payByTranchedStream(
        Types.Invoice memory invoice,
        address recipient
    ) internal returns (uint256 streamId) {
        uint40 numberOfTranches =
            Helpers.computeNumberOfPayments(invoice.payment.recurrence, invoice.endTime - invoice.startTime);

        streamId = StreamManager.createTranchedStream({
            asset: IERC20(invoice.payment.asset),
            totalAmount: invoice.payment.amount,
            startTime: invoice.startTime,
            recipient: recipient,
            numberOfTranches: numberOfTranches,
            recurrence: invoice.payment.recurrence
        });
    }

    /// @notice Calculates the number of payments to be made for a recurring transfer and tranched stream-based invoice
    /// @dev Reverts if the number of payments is zero, indicating that either the interval or recurrence type was set incorrectly
    function _checkIntervalPayments(
        Types.Recurrence recurrence,
        uint40 startTime,
        uint40 endTime
    ) internal pure returns (uint40 numberOfPayments) {
        // Checks: the invoice payment interval matches the recurrence type
        // This cannot underflow as the start time is stricly lower than the end time when this call executes
        uint40 interval;
        unchecked {
            interval = endTime - startTime;
        }

        // Check and calculate the expected number of payments based on the invoice recurrence and payment interval
        numberOfPayments = Helpers.computeNumberOfPayments(recurrence, interval);

        // Revert if there are zero payments to be made since the payment method due to invalid interval and recurrence type
        if (numberOfPayments == 0) {
            revert Errors.PaymentIntervalTooShortForSelectedRecurrence();
        }
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return _collectionURI;
    }
}
