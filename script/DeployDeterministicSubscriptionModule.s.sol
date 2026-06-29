// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { SubscriptionModule } from "src/modules/subscription-module/SubscriptionModule.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Deterministically deploys an instance of {SubscriptionModule}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicSubscriptionModule is BaseScript {
    function run(
        string memory inputSalt,
        address treasury
    )
        public
        virtual
        broadcast
        returns (SubscriptionModule subscriptionModule)
    {
        // Construct the CREATE3 salt based on the contract name and the provided input salt
        bytes32 salt = constructCreate3Salt("SubscriptionModule", inputSalt);

        // Deploy the {SubscriptionModule} implementation (non-deterministic)
        address subscriptionModuleImplementation = address(new SubscriptionModule());

        // Encode initialization data for the proxy constructor
        bytes memory initData =
            abi.encodeWithSelector(SubscriptionModule.initialize.selector, DEFAULT_PROTOCOL_ADMIN, treasury);

        // Construct the ERC1967Proxy bytecode with implementation and initData
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(subscriptionModuleImplementation, initData));

        // Deploy the proxy deterministically using CREATE3
        subscriptionModule = SubscriptionModule(CREATE3.deployDeterministic(proxyBytecode, salt));
    }
}
