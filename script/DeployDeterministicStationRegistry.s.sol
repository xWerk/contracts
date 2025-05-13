// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { StationRegistry } from "./../src/StationRegistry.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";

/// @notice Deploys at deterministic addresses across chains an instance of {StationRegistry}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicStationRegistry is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        ModuleKeeper moduleKeeper
    )
        public
        virtual
        broadcast
        returns (StationRegistry stationRegistry)
    {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {StationRegistry} smart account factory
        stationRegistry =
            new StationRegistry{ salt: salt }(DEFAULT_PROTOCOL_OWNER, IEntryPoint(ENTRYPOINT_V6), moduleKeeper);
    }
}
