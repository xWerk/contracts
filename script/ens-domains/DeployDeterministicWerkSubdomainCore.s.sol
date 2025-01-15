// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkSubdomainRegistrar } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistrar.sol";
import { WerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistry.sol";
import { IWerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/interfaces/IWerkSubdomainRegistry.sol";

/// @notice Deploys at deterministic addresses across chains the Werk's L2 subdomain core contracts
/// initializing the {WerkSubdomainRegistry} and adding the {WerkSubdomainRegistrar} as a registrar on the registry
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicWerkSubdomainCore is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        string memory ensDomain,
        string memory baseUri,
        address owner
    )
        public
        virtual
        broadcast
        returns (WerkSubdomainRegistry registry, WerkSubdomainRegistrar subdomainRegistrar)
    {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {WerkSubdomainRegistrar} contract
        registry = new WerkSubdomainRegistry{ salt: salt }();

        // Initialize the registry
        registry.initialize({ tokenName: ensDomain, tokenSymbol: ensDomain, _baseUri: baseUri });

        // Deterministically deploy the {WerkSubdomainRegistrar} contract
        subdomainRegistrar = new WerkSubdomainRegistrar{ salt: salt }(IWerkSubdomainRegistry(address(registry)), owner);

        // Add the registrar to the registry
        registry.addRegistrar({ registrar: address(subdomainRegistrar) });
    }
}
