// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { L2SubdomainRegistrar } from "./../src/peripherals/ens-domains/L2SubdomainRegistrar.sol";
import { IL2Registry } from "./../src/peripherals/ens-domains/interfaces/IL2Registry.sol";

/// @notice Deploys at deterministic addresses across chains the {L2SubdomainRegistrar} contract
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicL2SubdomainRegistrar is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        IL2Registry registry,
        address owner
    )
        public
        virtual
        broadcast
        returns (L2SubdomainRegistrar subdomainRegistrar)
    {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {L2SubdomainRegistrar} contract
        subdomainRegistrar = new L2SubdomainRegistrar{ salt: salt }(registry, owner);
    }
}
