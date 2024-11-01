// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title IInvoiceModule
/// @notice Contract module that provides functionalities to issue and pay an on-chain invoice
interface IInvoiceModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an invoice is created
    /// @param id The ID of the invoice
    /// @param recipient The address receiving the payment
    /// @param status The status of the invoice
    /// @param startTime The timestamp when the invoice takes effect
    /// @param endTime The timestamp by which the invoice must be paid
    /// @param payment Struct representing the payment details associated with the invoice
    event InvoiceCreated(
        uint256 id,
        address indexed recipient,
        Types.Status status,
        uint40 startTime,
        uint40 endTime,
        Types.Payment payment
    );

    /// @notice Emitted when an invoice is paid
    /// @param id The ID of the invoice
    /// @param payer The address of the payer
    /// @param status The status of the invoice
    /// @param payment Struct representing the payment details associated with the invoice
    event InvoicePaid(uint256 indexed id, address indexed payer, Types.Status status, Types.Payment payment);

    /// @notice Emitted when an invoice is canceled
    /// @param id The ID of the invoice
    event InvoiceCanceled(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the details of the `id` invoice
    /// @param id The ID of the invoice for which to get the details
    function getInvoice(uint256 id) external view returns (Types.Invoice memory invoice);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new invoice
    ///
    /// Requirements:
    /// - `msg.sender` must be a contract implementing the {ISpace} interface
    ///
    /// Notes:
    /// - `recipient` is not checked because the call is enforced to be made through a {Space} contract
    ///
    /// @param invoice The details of the invoice following the {Invoice} struct format
    /// @return id The on-chain ID of the invoice
    function createInvoice(Types.Invoice calldata invoice) external returns (uint256 id);

    /// @notice Pays a transfer-based invoice
    ///
    /// Notes:
    /// - `msg.sender` is enforced to be a specific payer address
    ///
    /// @param id The ID of the invoice to pay
    function payInvoice(uint256 id) external payable;

    /// @notice Cancels the `id` invoice
    ///
    /// Notes:
    /// - A transfer-based invoice can be canceled only by its creator (recipient)
    /// - A linear/tranched stream-based invoice can be canceled by its creator only if its
    /// status is `Pending`; otherwise only the stream sender can cancel it
    /// - if the invoice has a linear or tranched stream payment method, the streaming flow will be
    /// stopped and the remaining funds will be refunded to the stream payer
    ///
    /// Important:
    /// - if the invoice has a linear or tranched stream payment method, the portion that has already
    /// been streamed is NOT automatically transferred
    ///
    /// @param id The ID of the invoice
    function cancelInvoice(uint256 id) external;

    /// @notice Withdraws the maximum withdrawable amount from the stream associated with the `id` invoice
    ///
    /// Notes:
    /// - reverts if `msg.sender` is not the stream recipient
    /// - reverts if the payment method of the `id` invoice is not linear or tranched stream based
    ///
    /// @param id The ID of the invoice
    function withdrawInvoiceStream(uint256 id) external returns (uint128 withdrawnAmount);
}
