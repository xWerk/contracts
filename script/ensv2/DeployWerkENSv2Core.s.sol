// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkENSv2Deployer } from "./WerkENSv2Deployer.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "./../../src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";

/// @notice Deploys the Werk ENSv2 infrastructure: the Werk registry and resolver as ENSv2 proxies, and the
///  {WerkRegistrar}, then grants the registrar its roles and links the registry to "werk.eth" in both directions
/// @dev Broadcasts explicitly from `DEFAULT_PROTOCOL_ADMIN` as it holds the roles needed by the post-deployment calls
/// Requires `DEFAULT_PROTOCOL_ADMIN` to own "werk.eth" on the ETH registry
contract DeployWerkENSv2Core is BaseScript {
    /// @notice Thrown when there is no ENSv2 `ETHRegistry` deployment known for the current chain
    error UnsupportedChain(uint256 chainId);

    function run(
        IVerifiableFactory verifiableFactory,
        address userRegistryImpl,
        address permissionedResolverImpl
    )
        public
        virtual
        returns (IPermissionedRegistry werkRegistry, address werkResolver, WerkRegistrar werkRegistrar)
    {
        // Checks: the ENSv2 `ETHRegistry` is known for the current chain
        IPermissionedRegistry ethRegistry = IPermissionedRegistry(ensv2EthRegistryMap[block.chainid]);
        if (address(ethRegistry) == address(0)) revert UnsupportedChain(block.chainid);

        vm.startBroadcast(DEFAULT_PROTOCOL_ADMIN);

        // Step 1: Deploy the Werk registry as a `UserRegistry` proxy
        werkRegistry = WerkENSv2Deployer.deployRegistry(
            verifiableFactory, userRegistryImpl, WerkENSv2Deployer.REGISTRY_SALT, DEFAULT_PROTOCOL_ADMIN
        );

        // Step 2: Deploy the Werk resolver as a `PermissionedResolver` proxy
        werkResolver = WerkENSv2Deployer.deployResolver(
            verifiableFactory, permissionedResolverImpl, WerkENSv2Deployer.RESOLVER_SALT, DEFAULT_PROTOCOL_ADMIN
        );

        // Step 3: Deploy the `WerkRegistrar` as an ERC1967 proxy
        werkRegistrar = WerkENSv2Deployer.deployRegistrar(
            werkRegistry, werkResolver, DEFAULT_PROTOCOL_ADMIN, DEFAULT_BACKEND_SIGNER
        );

        // Step 4: Grant the `WerkRegistrar` its roles and link the registry to its canonical parent
        WerkENSv2Deployer.configure(werkRegistry, werkResolver, address(werkRegistrar), ethRegistry);

        // Step 5: Point "werk.eth" on the ETH registry to the Werk registry so that its subnames resolve
        ethRegistry.setSubregistry(uint256(keccak256("werk")), werkRegistry);

        vm.stopBroadcast();
    }
}
