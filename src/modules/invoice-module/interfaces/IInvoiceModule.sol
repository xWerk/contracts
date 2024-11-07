// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IInvoiceModule
/// @notice Contract module that provides functionalities to issue and pay an on-chain invoice
interface IInvoiceModule {
    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates an on-chain representation of an off-chain invoice by minting an ERC-721 token
    /// @param to The address to which the NFT will be minted
    /// @param paymentRequestId The ID of the payment request to which this invoice belongs
    function mint(address to, uint256 paymentRequestId) external;
}
