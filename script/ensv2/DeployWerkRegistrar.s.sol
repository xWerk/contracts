// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkENSv2Deployer } from "./WerkENSv2Deployer.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";

/// @notice Deploys the {WerkRegistrar} contract as an ERC1967 proxy owned by the protocol admin
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
        // Deploy the {WerkRegistrar} implementation and proxy
        werkRegistrar =
            WerkENSv2Deployer.deployRegistrar(werkRegistry, resolver, DEFAULT_PROTOCOL_ADMIN, DEFAULT_BACKEND_SIGNER);
    }
}
