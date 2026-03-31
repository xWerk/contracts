// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IModuleKeeper } from "./IModuleKeeper.sol";
import { ISpace } from "./ISpace.sol";

/// @title IStationRegistry
/// @notice Contract that provides functionalities to create stations and deploy {Space}s from a single place
interface IStationRegistry {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new {Space} contract gets deployed
    /// @param admin The address of the Space admin
    /// @param space The address of the {Space}
    event SpaceCreated(address indexed admin, address space);

    /// @notice Emitted when the {ModuleKeeper} address is updated
    /// @param newModuleKeeper The new address of the {ModuleKeeper}
    event ModuleKeeperUpdated(IModuleKeeper newModuleKeeper);

    /// @notice Emitted when the {Space} implementation address is updated
    /// @param newSpaceImplementation The new address of the {Space} implementation
    event SpaceImplementationUpdated(ISpace newSpaceImplementation);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the current version of the StationRegistry implementation
    function VERSION() external view returns (string memory);

    /// @notice Returns the address of the {ModuleKeeper} contract
    function moduleKeeper() external view returns (IModuleKeeper);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new {Space} contract
    ///
    /// @param _admin The ID of the station to attach the {Space} to
    /// @param _data Initialization data of the {Space} account
    function createAccount(address _admin, bytes calldata _data) external returns (address space);

    /// @notice Updates the address of the {ModuleKeeper}
    ///
    /// Notes:
    /// - does not check for zero-address;
    ///
    /// Requirements:
    /// - reverts if `msg.sender` is not the {StationRegistry} owner
    ///
    /// @param newModuleKeeper The new address of the {ModuleKeeper}
    function updateModuleKeeper(IModuleKeeper newModuleKeeper) external;

    /// @notice Updates the address of the {Space} account implementation
    ///
    /// Notes:
    /// - does not check for zero-address;
    ///
    /// Requirements:
    /// - reverts if `msg.sender` is not the {StationRegistry} owner
    /// @param newSpaceImplementation The new address of the {Space} implementation
    function updateSpaceImplementation(ISpace newSpaceImplementation) external;
}
