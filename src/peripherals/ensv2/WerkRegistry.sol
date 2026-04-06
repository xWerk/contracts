// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PermissionedRegistry } from "@ensv2/registry/PermissionedRegistry.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";

/// @title WerkRegistry
/// @notice Dedicated ENSv2 `PermissionedRegistry` instance for subnames under `werk.eth`
/// @dev Thin wrapper around `PermissionedRegistry` with an explicit type for Werk
contract WerkRegistry is PermissionedRegistry {
    /// @param hcaFactory Hierarchical component authority factory
    /// @param metadataProvider Metadata provider for registry entries
    /// @param ownerAddress Initial owner that receives `ownerRoles` on the root resource
    /// @param ownerRoles Role bitmap granted to `ownerAddress` on the root resource
    constructor(
        IHCAFactoryBasic hcaFactory,
        IRegistryMetadata metadataProvider,
        address ownerAddress,
        uint256 ownerRoles
    )
        PermissionedRegistry(hcaFactory, metadataProvider, ownerAddress, ownerRoles)
    { }
}
