// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "../Base.s.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/src/Options.sol";

/// @notice Upgrades the {CompensationModule} module based on a previous build
contract UpgradeCompensationModule is BaseScript {
    function run(address compensationModule) public virtual broadcast {
        Options memory opts;
        opts.referenceBuildInfoDir = "./out-optimized-old/build-info-v1/";
        opts.referenceContract = "build-info-v1:CompensationModule";

        Upgrades.upgradeProxy(compensationModule, "CompensationModule.sol", "", opts);
    }
}
