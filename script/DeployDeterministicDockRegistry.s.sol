// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { DockRegistry } from "./../src/DockRegistry.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { EntryPoint } from "@thirdweb/contracts/prebuilts/account/utils/Entrypoint.sol";

/// @notice Deploys at deterministic addresses across chains an instance of {DockRegistry}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicDockRegistry is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        address initialAdmin,
        EntryPoint entrypoint,
        ModuleKeeper moduleKeeper
    ) public virtual broadcast returns (DockRegistry dockRegistry) {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {DockRegistry} smart account factory
        dockRegistry = new DockRegistry{ salt: salt }(initialAdmin, entrypoint, moduleKeeper);
    }
}
