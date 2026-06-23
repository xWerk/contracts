// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkRegistry } from "./../../src/peripherals/ensv2/WerkRegistry.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";
import { IPermissionedResolver } from "@ensv2/resolver/interfaces/IPermissionedResolver.sol";

/// @notice Deploys the Werk ENSv2 infrastructure: {WerkRegistry} and {WerkRegistrar},
///  then grants the necessary roles to the registrar on both the registry and resolver
/// @dev Post-deployment, the "werk.eth" owner must set the deployed {WerkRegistry} as the
///  subregistry for the "werk" label on the ETH registry
///  e.g. ethRegistry.setSubregistry("werk", address(werkRegistry))
contract DeployWerkENSv2Core is BaseScript {
    function run(
        IHCAFactoryBasic hcaFactory,
        IRegistryMetadata metadataProvider,
        address resolver
    )
        public
        virtual
        broadcast
        returns (WerkRegistry werkRegistry, WerkRegistrar werkRegistrar)
    {
        // Step 1: Deploy WerkRegistry with full owner roles
        uint256 ownerRoles = RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_REGISTRAR
            | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
            | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_RENEW_ADMIN;

        werkRegistry = new WerkRegistry(hcaFactory, metadataProvider, DEFAULT_PROTOCOL_ADMIN, ownerRoles);

        // Step 2: Deploy WerkRegistrar
        werkRegistrar =
            new WerkRegistrar(IPermissionedRegistry(address(werkRegistry)), resolver, DEFAULT_PROTOCOL_ADMIN);

        // Step 3: Grant ROLE_REGISTRAR to WerkRegistrar on WerkRegistry
        werkRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(werkRegistrar));

        // Step 4: Grant resolver write permissions to WerkRegistrar
        uint256 ROLE_SET_ADDR = 1 << 0;
        uint256 ROLE_SET_ADDR_ADMIN = ROLE_SET_ADDR << 128;
        IPermissionedResolver(resolver).grantRootRoles(ROLE_SET_ADDR | ROLE_SET_ADDR_ADMIN, address(werkRegistrar));
    }
}
