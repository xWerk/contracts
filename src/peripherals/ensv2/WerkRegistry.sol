// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PermissionedRegistry } from "@ensv2/registry/PermissionedRegistry.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";

/// @title WerkRegistry
/// @notice Dedicated ENSv2 `PermissionedRegistry` instance for subnames under `werk.eth`
/// @dev Thin wrapper around `PermissionedRegistry` with an explicit type for Werk
contract WerkRegistry is PermissionedRegistry {
    /// @param hcaFactory_ Hierarchical component authority factory
    /// @param metadataProvider_ Metadata provider for registry entries
    /// @param ownerAddress_ Initial owner that receives `ownerRoles_` on the root resource
    /// @param ownerRoles_ Role bitmap granted to `ownerAddress_` on the root resource
    constructor(
        IHCAFactoryBasic hcaFactory_,
        IRegistryMetadata metadataProvider_,
        address ownerAddress_,
        uint256 ownerRoles_
    )
        PermissionedRegistry(hcaFactory_, metadataProvider_, ownerAddress_, ownerRoles_)
    { }
}
