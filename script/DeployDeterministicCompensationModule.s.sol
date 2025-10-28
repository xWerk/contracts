// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";

/// @notice Deterministically deploys an instance of {CompensationModule}
/// @dev Uses `CREATE3` for deterministic proxy deployment across all EVM chains
contract DeployCompensationModule is BaseScript {
    function run() public virtual broadcast returns (CompensationModule compensationModule) {
        // Create deterministic salt
        bytes32 salt = createSalt("CompensationModule");

        // Deploy the {CompensationModule} implementation (non-deterministic)
        address compensationModuleImplementation = address(new CompensationModule());

        // Encode initialization data for the proxy constructor
        bytes memory initData = abi.encodeWithSelector(
            CompensationModule.initialize.selector, ISablierFlow(sablierFlowMap[block.chainid]), DEFAULT_PROTOCOL_OWNER
        );

        // Construct the ERC1967Proxy bytecode with implementation and initData
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(compensationModuleImplementation, initData));

        // Deploy the proxy deterministically using CREATE3
        compensationModule = CompensationModule(CREATE3.deployDeterministic(proxyBytecode, salt));
    }
}
