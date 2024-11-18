// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { InvoiceCollection } from "../src/peripherals/invoice-collection/InvoiceCollection.sol";

/// @notice Deploys and initializes the {InvoiceCollection} contract at deterministic addresses across chains
/// @dev Reverts if any contract has already been deployed
contract DeployInvoiceCollection is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        address relayer,
        string memory name,
        string memory symbol
    )
        public
        virtual
        broadcast
        returns (InvoiceCollection invoiceCollection)
    {
        // Deploy the {InvoiceCollection} contract
        invoiceCollection = new InvoiceCollection(relayer, name, symbol);
    }
}
