// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IInvoiceCollection
/// @notice Peripheral contract that provides functionalities to mint ERC-721 tokens representing off-chain invoices
interface IInvoiceCollection {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an invoice is created
    /// @param to The address of the payment recipient of the invoice
    /// @param tokenId The ID of the NFT representing the invoice
    /// @param paymentRequestId The ID of the payment request associated with the invoice
    event InvoiceMinted(address to, uint256 tokenId, string paymentRequestId);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates an on-chain representation of an off-chain invoice by creating a payment request and minting an ERC-721 token
    /// @param invoiceURI The metadata URI of the invoice
    /// @param paymentRecipient The address of the payment recipient of the invoice
    /// @param paymentRequestId The ID of the payment request associated with the invoice
    /// @return tokenId The ID of the NFT representing the invoice
    function mintInvoice(
        string memory invoiceURI,
        address paymentRecipient,
        string memory paymentRequestId
    )
        external
        returns (uint256 tokenId);
}
