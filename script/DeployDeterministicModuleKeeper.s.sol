// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";

/// @notice Deploys the {ModuleKeeper} contract at deterministic addresses across chains
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicModuleKeeper is BaseScript {
    function run(string memory inputSalt) public virtual broadcast returns (ModuleKeeper moduleKeeper) {
        // Construct the CREATE3 salt based on the contract name and the provided input salt
        bytes32 salt = constructCreate3Salt("ModuleKeeper", inputSalt);

        // Deterministically deploy the {ModuleKeeper} contract
        bytes memory args = abi.encode(DEFAULT_PROTOCOL_ADMIN);
        bytes memory moduleKeeperInitCode = abi.encodePacked(vm.getCode("ModuleKeeper.sol"), args);
        moduleKeeper = ModuleKeeper(CREATE3.deployDeterministic(moduleKeeperInitCode, salt));
    }
}
