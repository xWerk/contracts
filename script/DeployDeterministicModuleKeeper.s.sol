// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";

/// @notice Deploys at deterministic addresses across chains the {ModuleKeeper} contract
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicModuleKeeper is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(string memory create2Salt) public virtual broadcast returns (ModuleKeeper moduleKeeper) {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {ModuleKeeper} contract
        moduleKeeper = new ModuleKeeper{ salt: salt }(DEFAULT_PROTOCOL_OWNER);
    }
}
