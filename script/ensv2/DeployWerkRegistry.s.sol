// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkENSv2Deployer } from "./WerkENSv2Deployer.sol";
import { IVerifiableFactory } from "./../../src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";

/// @notice Deploys the Werk registry as an ENSv2 `UserRegistry` proxy with the admin roles granted to the protocol admin
/// @dev Uses its own salt so that it never collides with the registry deployed by {DeployWerkENSv2Core}
contract DeployWerkRegistry is BaseScript {
    /// @dev `VerifiableFactory` salt of the standalone Werk registry
    uint256 internal constant STANDALONE_REGISTRY_SALT = uint256(keccak256("WerkRegistry.standalone"));

    function run(
        IVerifiableFactory verifiableFactory,
        address userRegistryImpl
    )
        public
        virtual
        broadcast
        returns (IPermissionedRegistry werkRegistry)
    {
        // Deploy the Werk registry proxy
        werkRegistry = WerkENSv2Deployer.deployRegistry(
            verifiableFactory, userRegistryImpl, STANDALONE_REGISTRY_SALT, DEFAULT_PROTOCOL_ADMIN
        );
    }
}
