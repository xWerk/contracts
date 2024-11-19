// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title Errors
/// @notice Library containing all custom errors the {InvoiceCollection} may revert with
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    INVOICE-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is unathorized to execute a call
    error Unauthorized();
}
