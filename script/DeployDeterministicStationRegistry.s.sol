// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { StationRegistry } from "src/StationRegistry.sol";
import { Space } from "src/Space.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";

/// @notice Deterministically deploys an instance of {StationRegistry}
/// @dev Reverts if any contract has already been deployed
///
/// Notes:
/// The deployment follows a two-step approach to resolve the circular dependency
/// between {StationRegistry} and {Space}: the proxy is deployed first without
/// initialization, then {Space} is deployed with the proxy address, and finally
/// the proxy is initialized with the {Space} implementation address
contract DeployDeterministicStationRegistry is BaseScript {
    function run(
        string memory inputSalt,
        ModuleKeeper moduleKeeper
    )
        public
        virtual
        broadcast
        returns (StationRegistry stationRegistry, Space spaceImplementation)
    {
        // Construct the CREATE3 salt based on the contract name and the provided input salt
        bytes32 salt = constructCreate3Salt("StationRegistry", inputSalt);

        // Deploy the {StationRegistry} implementation (non-deterministic)
        address implementation = address(new StationRegistry());

        // Deploy the proxy deterministically using CREATE3 without initialization
        // to resolve the circular dependency with {Space}
        bytes memory emptyData;
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, emptyData));
        address proxy = CREATE3.deployDeterministic(proxyBytecode, salt);

        // Deploy the {Space} implementation deterministically with the proxy address as factory
        spaceImplementation = _deploySpaceImplementation(inputSalt, proxy);

        // Initialize the {StationRegistry} proxy
        StationRegistry(proxy)
            .initialize(DEFAULT_PROTOCOL_ADMIN, IEntryPoint(ENTRYPOINT_V6), moduleKeeper, address(spaceImplementation));

        stationRegistry = StationRegistry(proxy);
    }

    /// @dev Deploys {Space} at a deterministic address across chains
    function _deploySpaceImplementation(
        string memory inputSalt,
        address stationRegistryProxy
    )
        internal
        returns (Space space)
    {
        // Construct the CREATE3 salt based on the contract name and the provided input salt
        bytes32 salt = constructCreate3Salt("Space", inputSalt);

        bytes memory args = abi.encode(IEntryPoint(ENTRYPOINT_V6), stationRegistryProxy);
        bytes memory spaceInitCode = abi.encodePacked(vm.getCode("Space.sol"), args);
        space = Space(payable(CREATE3.deployDeterministic(spaceInitCode, salt)));
    }
}
