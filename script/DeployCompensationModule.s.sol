// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";

import { Upgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";

/// @notice Deploys an instance of {CompensationModule}
contract DeployCompensationModule is BaseScript {
    function run() public virtual broadcast returns (CompensationModule compensationModule) {
        compensationModule = CompensationModule(
            Upgrades.deployUUPSProxy(
                "CompensationModule.sol",
                abi.encodeCall(
                    CompensationModule.initialize,
                    (
                        ISablierFlow(sablierFlowMap[block.chainid]),
                        DEFAULT_PROTOCOL_OWNER,
                        DEFAULT_BROKER_ADMIN,
                        DEFAULT_BROKER_FEE
                    )
                )
            )
        );
    }
}
