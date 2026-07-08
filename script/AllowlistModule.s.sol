// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";

/// @notice Adds a deployed module to the {ModuleKeeper} allowlist
/// @dev The broadcasting account MUST be the {ModuleKeeper} owner, as `addToAllowlist` is `onlyOwner`
contract AllowlistModule is BaseScript {
    function run(address moduleKeeper, address module) public virtual broadcast {
        address[] memory modules = new address[](1);
        modules[0] = module;

        ModuleKeeper(moduleKeeper).addToAllowlist(modules);
    }
}
