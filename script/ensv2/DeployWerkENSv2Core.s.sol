// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkENSv2Deployer } from "./WerkENSv2Deployer.sol";
import { WerkRegistrar } from "./../../src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "./../../src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";

/// @notice Deploys the Werk ENSv2 infrastructure: the Werk registry as an ENSv2 proxy and the {WerkRegistrar},
///  then grants the registrar its roles and links the registry to "werk.eth"
/// The subname owners' resolvers are deployed later by the {WerkRegistrar}, from `permissionedResolverImpl`
/// @dev Broadcasts explicitly from `DEFAULT_PROTOCOL_ADMIN` as it holds the roles needed by the post-deployment calls
/// Points "werk.eth" to the Werk registry only if `DEFAULT_PROTOCOL_ADMIN` owns it on the ETH registry; otherwise its
/// owner sets the subregistry itself
contract DeployWerkENSv2Core is BaseScript {
    /// @notice Thrown when there is no ENSv2 `ETHRegistry` deployment known for the current chain
    error UnsupportedChain(uint256 chainId);

    /// @dev Deploys the Werk registry with `registrySalt`
    /// Note: a new salt is needed to redeploy from the same broadcaster, as the registry address depends only on both
    function run(
        IVerifiableFactory verifiableFactory,
        address userRegistryImpl,
        address permissionedResolverImpl,
        uint256 registrySalt
    )
        public
        virtual
        returns (IPermissionedRegistry werkRegistry, WerkRegistrar werkRegistrar)
    {
        // Checks: the ENSv2 `ETHRegistry` is known for the current chain
        IPermissionedRegistry ethRegistry = IPermissionedRegistry(ensv2EthRegistryMap[block.chainid]);
        if (address(ethRegistry) == address(0)) revert UnsupportedChain(block.chainid);

        vm.startBroadcast(DEFAULT_PROTOCOL_ADMIN);

        // Step 1: Deploy the Werk registry as a `UserRegistry` proxy
        werkRegistry =
            WerkENSv2Deployer.deployRegistry(verifiableFactory, userRegistryImpl, registrySalt, DEFAULT_PROTOCOL_ADMIN);

        // Step 2: Deploy the `WerkRegistrar` as an ERC1967 proxy
        werkRegistrar = WerkENSv2Deployer.deployRegistrar(
            werkRegistry, verifiableFactory, permissionedResolverImpl, DEFAULT_PROTOCOL_ADMIN, DEFAULT_BACKEND_SIGNER
        );

        // Step 3: Grant the `WerkRegistrar` its roles and link the registry to its canonical parent
        WerkENSv2Deployer.configure(werkRegistry, address(werkRegistrar), ethRegistry);

        // Step 4: Point "werk.eth" on the ETH registry to the Werk registry so that its subnames resolve
        // Note: skipped if another account holds "werk.eth", e.g. the mainnet Safe
        uint256 werkLabelId = uint256(keccak256("werk"));
        if (ethRegistry.getState(werkLabelId).latestOwner == DEFAULT_PROTOCOL_ADMIN) {
            ethRegistry.setSubregistry(werkLabelId, werkRegistry);
        }

        vm.stopBroadcast();
    }
}
