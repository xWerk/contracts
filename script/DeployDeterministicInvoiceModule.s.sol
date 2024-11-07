// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { InvoiceModule } from "../src/modules/invoice-module/InvoiceModule.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

/// @notice Deploys and initializes the {InvoiceModule} contracts at deterministic addresses across chains
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicInvoiceModule is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        ISablierV2LockupLinear sablierLockupLinear,
        ISablierV2LockupTranched sablierLockupTranched,
        address brokerAdmin,
        string memory baseURI
    ) public virtual broadcast returns (InvoiceModule invoiceModule) {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {InvoiceModule} contracts
        invoiceModule = new InvoiceModule{ salt: salt }(
            sablierLockupLinear,
            sablierLockupTranched,
            brokerAdmin,
            baseURI
        );
    }
}
