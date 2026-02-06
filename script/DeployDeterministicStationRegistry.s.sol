// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { StationRegistry } from "./../src/StationRegistry.sol";
import { Space } from "./../src/Space.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";

/// @notice Deterministically deploys an instance of {StationRegistry}
/// @dev Uses `CREATE3` for deterministic proxy deployment across all EVM chains
/// The deployment follows a two-step approach to resolve the circular dependency
/// between {StationRegistry} and {Space}: the proxy is deployed first without
/// initialization, then {Space} is deployed with the proxy address, and finally
/// the proxy is initialized with the {Space} implementation address
contract DeployDeterministicStationRegistry is BaseScript {
    function run(
        string memory salt,
        ModuleKeeper moduleKeeper
    )
        public
        virtual
        broadcast
        returns (StationRegistry stationRegistry)
    {
        // Create deterministic salt
        bytes32 create3Salt = create3Salt("StationRegistry", salt);

        // Deploy the {StationRegistry} implementation (non-deterministic)
        address implementation = address(new StationRegistry());

        // Deploy the proxy deterministically using CREATE3 without initialization
        // to resolve the circular dependency with {Space}
        bytes memory emptyData;
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, emptyData));
        address proxy = CREATE3.deployDeterministic(proxyBytecode, create3Salt);

        // Deploy {Space} implementation with the proxy address as factory
        Space spaceImplementation = new Space(IEntryPoint(ENTRYPOINT_V6), proxy);

        // Initialize the {StationRegistry} proxy
        StationRegistry(proxy)
            .initialize(DEFAULT_PROTOCOL_ADMIN, IEntryPoint(ENTRYPOINT_V6), moduleKeeper, address(spaceImplementation));

        stationRegistry = StationRegistry(proxy);
    }
}
