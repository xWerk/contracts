// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { Space } from "../src/Space.sol";
import { DockRegistry } from "./../src/DockRegistry.sol";

/// @notice Deploys an instance of {Space} and enables initial module(s)
contract DeployContainer is BaseScript {
    function run(
        address initialAdmin,
        DockRegistry dockRegistry,
        uint256 dockId,
        address[] memory initialModules
    ) public virtual broadcast returns (Space space) {
        // Get the number of total accounts created by the `initialAdmin` deployer
        uint256 totalAccountsOfAdmin = dockRegistry.totalAccountsOfSigner(initialAdmin);

        // Construct the ABI-encoded data to be passed to the `createAccount` method
        bytes memory data = abi.encode(totalAccountsOfAdmin, dockId, initialModules);

        // Deploy a new {Space} smart account through the {DockRegistry} account factory
        space = Space(payable(dockRegistry.createAccount(initialAdmin, data)));
    }
}
