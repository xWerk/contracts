// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Errors } from "./libraries/Errors.sol";
import { IInvoiceCollection } from "./interfaces/IInvoiceCollection.sol";

/// @title InvoiceCollection
/// @notice See the documentation in {IInvoiceCollection}
contract InvoiceCollection is IInvoiceCollection, ERC721URIStorage {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The address of the off-chain Relayer responsible to mint on-chain invoices
    address public relayer;

    /// @dev Token ID of the invoicemapped to the payment request ID
    mapping(uint256 tokenId => string paymentRequestId) public tokenIdToPaymentRequestId;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Counter to keep track of the next ID used to mint a new token per invoice
    uint256 private _nextTokenId;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {InvoiceCollection} contract
    constructor(address _relayer, string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        // Set the authorized Relayer
        relayer = _relayer;

        // Start the invoice token IDs from 1
        _nextTokenId = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInvoiceCollection
    function mintInvoice(
        string memory invoiceURI,
        address paymentRecipient,
        string memory paymentRequestId
    )
        public
        returns (uint256 tokenId)
    {
        // Checks: `msg.sender` is the authorized Relayer to mint tokens
        if (msg.sender != relayer) {
            revert Errors.Unauthorized();
        }

        // Get the next token ID
        tokenId = _nextTokenId;

        // Effects: increment the next token ID
        // Use unchecked because the token ID cannot realistically overflow
        unchecked {
            ++_nextTokenId;
        }

        // Effects: set the `paymentRequestId` that belongs to the `tokenId` invoice
        tokenIdToPaymentRequestId[tokenId] = paymentRequestId;

        // Effects: mint the invoice NFT to the payment recipient
        _mint({ to: paymentRecipient, tokenId: tokenId });

        // Effects: set the `invoiceURI` for the `tokenId` invoice
        _setTokenURI(tokenId, invoiceURI);

        // Log the invoice minting
        emit InvoiceMinted({ to: paymentRecipient, tokenId: tokenId, paymentRequestId: paymentRequestId });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    INTERNAL-METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC721
    /// @dev Guard tokens from being transferred making them Soulbound Tokens (SBT)
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721) returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("Soulbound token!");
        }

        return super._update(to, tokenId, auth);
    }
}
