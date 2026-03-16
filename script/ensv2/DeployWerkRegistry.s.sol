// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkRegistry } from "./../../src/peripherals/ensv2/WerkRegistry.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";

/// @notice Deploys the {WerkRegistry} contract with full owner roles
contract DeployWerkRegistry is BaseScript {
    function run(
        IHCAFactoryBasic hcaFactory,
        IRegistryMetadata metadataProvider
    )
        public
        virtual
        broadcast
        returns (WerkRegistry werkRegistry)
    {
        // Compute the owner roles bitmap
        uint256 ownerRoles = RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_REGISTRAR
            | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
            | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_RENEW_ADMIN;

        // Deploy the {WerkRegistry} contract
        werkRegistry = new WerkRegistry(hcaFactory, metadataProvider, DEFAULT_PROTOCOL_ADMIN, ownerRoles);
    }
}
