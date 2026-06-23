// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";

/// @notice Deploys the {WerkRegistrar} contract
contract DeployWerkRegistrar is BaseScript {
    function run(
        IPermissionedRegistry werkRegistry,
        address resolver
    )
        public
        virtual
        broadcast
        returns (WerkRegistrar werkRegistrar)
    {
        // Deploy the {WerkRegistrar} contract
        werkRegistrar = new WerkRegistrar(werkRegistry, resolver, DEFAULT_PROTOCOL_ADMIN);
    }
}
