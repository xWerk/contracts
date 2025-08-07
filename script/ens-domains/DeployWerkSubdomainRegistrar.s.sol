// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./../Base.s.sol";
import { WerkSubdomainRegistrar } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistrar.sol";
import { IWerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/interfaces/IWerkSubdomainRegistry.sol";

/// @notice Deploys the {WerkSubdomainRegistrar} contract
contract DeployWerkSubdomainRegistrar is BaseScript {
    function run(IWerkSubdomainRegistry registry)
        public
        virtual
        broadcast
        returns (WerkSubdomainRegistrar subdomainRegistrar)
    {
        // Deploy the {WerkSubdomainRegistrar} contract
        subdomainRegistrar = new WerkSubdomainRegistrar(registry, DEFAULT_PROTOCOL_OWNER);
    }
}
