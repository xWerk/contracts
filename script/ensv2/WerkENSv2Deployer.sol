// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IVerifiableFactory } from "./../../src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";
import { PermissionedResolverLib } from "@ensv2/resolver/libraries/PermissionedResolverLib.sol";
import { IPermissionedResolverInitializable } from "@ensv2/resolver/interfaces/IPermissionedResolverInitializable.sol";
import { Grant, IEACGrantInitializable } from "@ensv2/access-control/interfaces/IEACGrantInitializable.sol";
import { IEnhancedAccessControl } from "@ensv2/access-control/interfaces/IEnhancedAccessControl.sol";

/// @title WerkENSv2Deployer
/// @notice Shared deployment logic for the Werk ENSv2 registry and resolver proxies
/// @dev Used by both the deployment scripts and the fork tests so that they exercise the same roles and salts
library WerkENSv2Deployer {
    /// @dev Root roles granted to the Werk admin on the Werk registry
    /// Note: `ROLE_REGISTRAR`, `ROLE_UNREGISTER` and `ROLE_SET_RESOLVER` are granted as admin-only roles so that the
    /// admin cannot register, unregister or repoint subnames directly and desync the {WerkRegistrar} mappings, while
    /// still being able to grant `ROLE_REGISTRAR` to the {WerkRegistrar}
    uint256 internal constant REGISTRY_ADMIN_ROLES = RegistryRolesLib.ROLE_REGISTRAR_ADMIN
        | RegistryRolesLib.ROLE_UNREGISTER_ADMIN | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
        | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN | RegistryRolesLib.ROLE_RENEW
        | RegistryRolesLib.ROLE_RENEW_ADMIN | RegistryRolesLib.ROLE_UPGRADE | RegistryRolesLib.ROLE_UPGRADE_ADMIN;

    /// @dev Root roles granted to the Werk admin on the Werk resolver
    /// Note: `ROLE_SET_ADDRESS` is granted as an admin-only role so that the admin cannot overwrite the address
    /// records of the spaces' subnames, while still being able to grant it to the {WerkRegistrar}
    uint256 internal constant RESOLVER_ADMIN_ROLES = PermissionedResolverLib.ROLE_SET_ADDRESS_ADMIN
        | PermissionedResolverLib.ROLE_UPGRADE | PermissionedResolverLib.ROLE_UPGRADE_ADMIN;

    /// @dev `VerifiableFactory` salt of the Werk registry deployed by {DeployWerkENSv2Core}
    /// Note: the factory mixes in the deployer, so the proxy address is unique per broadcaster
    uint256 internal constant REGISTRY_SALT = uint256(keccak256("WerkRegistry"));

    /// @dev `VerifiableFactory` salt of the Werk resolver deployed by {DeployWerkENSv2Core}
    uint256 internal constant RESOLVER_SALT = uint256(keccak256("WerkResolver"));

    /// @dev Deploys the Werk registry as a `UserRegistry` proxy with `REGISTRY_ADMIN_ROLES` granted to `admin`
    function deployRegistry(
        IVerifiableFactory verifiableFactory,
        address userRegistryImpl,
        uint256 salt,
        address admin
    )
        internal
        returns (IPermissionedRegistry)
    {
        Grant[] memory grants = new Grant[](1);
        grants[0] = Grant({ account: admin, roleBitmap: REGISTRY_ADMIN_ROLES });

        return IPermissionedRegistry(
            verifiableFactory.deployProxy(
                userRegistryImpl, salt, abi.encodeCall(IEACGrantInitializable.initialize, (grants))
            )
        );
    }

    /// @dev Deploys the Werk resolver as a `PermissionedResolver` proxy with `RESOLVER_ADMIN_ROLES` granted to `admin`
    function deployResolver(
        IVerifiableFactory verifiableFactory,
        address permissionedResolverImpl,
        uint256 salt,
        address admin
    )
        internal
        returns (address)
    {
        Grant[] memory grants = new Grant[](1);
        grants[0] = Grant({ account: admin, roleBitmap: RESOLVER_ADMIN_ROLES });

        return verifiableFactory.deployProxy(
            permissionedResolverImpl,
            salt,
            abi.encodeCall(IPermissionedResolverInitializable.initialize, (grants, new bytes[](0)))
        );
    }

    /// @dev Grants the {WerkRegistrar} its roles and links the Werk registry to its canonical parent
    /// Must be called by the Werk admin
    function configure(
        IPermissionedRegistry werkRegistry,
        address werkResolver,
        address werkRegistrar,
        IRegistry ethRegistry
    )
        internal
    {
        // Grant `ROLE_REGISTRAR` to the {WerkRegistrar} on the Werk registry
        werkRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, werkRegistrar);

        // Grant `ROLE_SET_ADDRESS` to the {WerkRegistrar} on the Werk resolver
        // Note: the admin role is intentionally omitted as the registrar never needs to grant it further
        IEnhancedAccessControl(werkResolver).grantRootRoles(PermissionedResolverLib.ROLE_SET_ADDRESS, werkRegistrar);

        // Set "werk" on the ETH registry as the canonical parent so that `<label>.werk.eth` is canonical
        werkRegistry.setParent(ethRegistry, "werk");
    }
}
