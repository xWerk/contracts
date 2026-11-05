// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "./../../src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";
import { Grant, IEACGrantInitializable } from "@ensv2/access-control/interfaces/IEACGrantInitializable.sol";

/// @title WerkENSv2Deployer
/// @notice Shared deployment logic for the Werk ENSv2 registry and registrar proxies
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

    /// @dev `VerifiableFactory` salt of the Werk registry deployed by {DeployWerkENSv2Core}
    /// Note: the factory mixes in the deployer, so the proxy address is unique per broadcaster
    uint256 internal constant REGISTRY_SALT = uint256(keccak256("WerkRegistry"));

    /// @dev Deploys the {WerkRegistrar} implementation behind an ERC1967 proxy owned by `admin`, trusting the
    /// signatures of `signer` and deploying the subname owners' resolvers from `resolverImpl`
    function deployRegistrar(
        IPermissionedRegistry werkRegistry,
        IVerifiableFactory verifiableFactory,
        address resolverImpl,
        address admin,
        address signer
    )
        internal
        returns (WerkRegistrar)
    {
        // Deploy the {WerkRegistrar} implementation
        address implementation = address(new WerkRegistrar());

        // Deploy the proxy and initialize it in the same transaction
        bytes memory initData =
            abi.encodeCall(WerkRegistrar.initialize, (werkRegistry, verifiableFactory, resolverImpl, admin, signer));
        return WerkRegistrar(address(new ERC1967Proxy(implementation, initData)));
    }

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

    /// @dev Grants the {WerkRegistrar} its roles and links the Werk registry to its canonical parent
    /// Must be called by the Werk admin
    /// Note: no resolver roles are granted here, as the {WerkRegistrar} deploys each owner's resolver itself
    function configure(IPermissionedRegistry werkRegistry, address werkRegistrar, IRegistry ethRegistry) internal {
        // Grant the {WerkRegistrar} the roles to register, renew and clear subnames on the Werk registry
        werkRegistry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_UNREGISTER,
            werkRegistrar
        );

        // Set "werk" on the ETH registry as the canonical parent so that `<label>.werk.eth` is canonical
        werkRegistry.setParent(ethRegistry, "werk");
    }
}
