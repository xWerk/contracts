// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";

/// @notice Adds one or more deployed modules to the {ModuleKeeper} allowlist in a single call
/// @dev The broadcasting account MUST be the {ModuleKeeper} owner, as `addToAllowlist` is `onlyOwner`.
/// Pass the modules as an array, e.g. `--sig "run(address,address[])" $MODULES "[0xAbc...,0xDef...]"`.
contract AllowlistModule is BaseScript {
    function run(address moduleKeeper, address[] calldata modules) public virtual broadcast {
        ModuleKeeper(moduleKeeper).addToAllowlist(modules);
    }
}
