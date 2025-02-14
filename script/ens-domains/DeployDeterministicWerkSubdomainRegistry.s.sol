// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistry.sol";

/// @notice Deploys at deterministic addresses across chains the {WerkSubdomainRegistry} contract
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicWerkSubdomainRegistry is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        string memory ensDomain,
        string memory baseUri
    )
        public
        virtual
        broadcast
        returns (WerkSubdomainRegistry registry)
    {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {WerkSubdomainRegistry} contract
        registry = new WerkSubdomainRegistry{ salt: salt }();

        // Initialize the registry
        registry.initialize({ tokenName: ensDomain, tokenSymbol: ensDomain, _baseUri: baseUri });
    }
}
