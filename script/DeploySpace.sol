// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { Space } from "../src/Space.sol";
import { StationRegistry } from "./../src/StationRegistry.sol";

/// @notice Deploys an instance of {Space} and enables initial module(s)
contract DeploySpace is BaseScript {
    function run(
        address initialAdmin,
        StationRegistry stationRegistry,
        uint256 stationId,
        address[] memory initialModules
    )
        public
        virtual
        broadcast
        returns (Space space)
    {
        // Get the number of total accounts created by the `initialAdmin` deployer
        uint256 totalAccountsOfAdmin = stationRegistry.totalAccountsOfSigner(initialAdmin);

        // Construct the ABI-encoded data to be passed to the `createAccount` method
        bytes memory data = abi.encode(totalAccountsOfAdmin, stationId, initialModules);

        // Deploy a new {Space} smart account through the {StationRegistry} account factory
        space = Space(payable(stationRegistry.createAccount(initialAdmin, data)));
    }
}
