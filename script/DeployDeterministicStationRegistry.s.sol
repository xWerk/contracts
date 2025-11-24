// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { StationRegistry } from "./../src/StationRegistry.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";

/// @notice Deploys at deterministic addresses across chains an instance of {StationRegistry}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicStationRegistry is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://getfoundry.sh/guides/deterministic-deployments-using-create2/#deterministic-deployments-using-create2
    function run(
        string memory salt,
        ModuleKeeper moduleKeeper
    ) public virtual broadcast returns (StationRegistry stationRegistry) {
        // Create deterministic salt
        bytes32 create3Salt = create3Salt("StationRegistry", salt);

        // Deploy the {StationRegistry} factory deterministically using CREATE2
        bytes memory args = abi.encode(DEFAULT_PROTOCOL_ADMIN, IEntryPoint(ENTRYPOINT_V6), moduleKeeper);
        bytes memory stationRegistryInitCode = abi.encodePacked(vm.getCode("StationRegistry.sol"), args);
        stationRegistry = StationRegistry(CREATE3.deployDeterministic(stationRegistryInitCode, create3Salt));
    }
}
