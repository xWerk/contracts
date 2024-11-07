// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

import { PaymentModule } from "./../payment-module/PaymentModule.sol";
import { IInvoiceModule } from "./interfaces/IInvoiceModule.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title InvoiceModule
/// @notice See the documentation in {IInvoiceModule}
contract InvoiceModule is IInvoiceModule, PaymentModule, ERC721 {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The address of the off-chain Relayer responsible to mint on-chain invoices
    address public relayer;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Invoice ID mapped to the payment request ID
    mapping(uint256 invoiceId => uint256 paymentRequestId) private _invoiceIdToPaymentRequest;

    /// @dev Counter to keep track of the next ID used to create a new invoice
    uint256 private _nextInvoiceId;

    /// @dev Base URI used to get the ERC-721 `tokenURI` metadata JSON schema
    string private _collectionURI;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {PaymentModule} and {ERC721} contracts
    constructor(
        ISablierV2LockupLinear _sablierLockupLinear,
        ISablierV2LockupTranched _sablierLockupTranched,
        address _brokerAdmin,
        string memory _URI
    )
        PaymentModule(_sablierLockupLinear, _sablierLockupTranched, _brokerAdmin)
        ERC721("Werk Invoice NFTs", "WK-INVOICES")
    {
        // Start the invoice IDs from 1
        _nextInvoiceId = 1;

        // Set the ERC721 baseURI
        _collectionURI = _URI;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Checks: the `tokenId` was minted or is not burned
        _requireOwned(tokenId);

        // Create the `tokenURI` by concatenating the `baseURI`, `tokenId` and metadata extension (.json)
        string memory baseURI = _baseURI();
        return string.concat(baseURI, tokenId.toString(), ".json");
    }

    /*//////////////////////////////////////////////////////////////////////////
                               NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInvoiceModule
    function mint(address to, uint256 paymentRequestId) public {
        // Checks: `msg.sender` is the authorized Relayer to mint tokens
        if (msg.sender != relayer) {
            revert Errors.Unathorized();
        }

        // Get the next token ID
        uint256 tokenId = _nextInvoiceId;

        // Effects: increment the next payment request ID
        // Use unchecked because the request  id cannot realistically overflow
        unchecked {
            ++_nextInvoiceId;
        }

        // Effects: set the `paymentRequestId` that belongs to the `tokenId` invoice
        _invoiceIdToPaymentRequest[tokenId] = paymentRequestId;

        // Effects: mint the request  NFT to the recipient space
        _mint(to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    INTERNAL-METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return _collectionURI;
    }

    /// @inheritdoc ERC721
    /// @dev Guard tokens from being transferred making them Soulbound Tokens (SBT)
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721) returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("Soulbound: Transfer failed");
        }

        return super._update(to, tokenId, auth);
    }
}
