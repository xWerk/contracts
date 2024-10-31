// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Container } from "./../Container.sol";
import { IModuleKeeper } from "./IModuleKeeper.sol";
import { ModuleKeeper } from "./../ModuleKeeper.sol";

/// @title IDockRegistry
/// @notice Contract that provides functionalities to create docks and deploy {Container}s from a single place
interface IDockRegistry {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new {Container} contract gets deployed
    /// @param owner The address of the owner
    /// @param dockId The ID of the dock to which this {Container} belongs
    /// @param container The address of the {Container}
    /// @param initialModules Array of initially enabled modules
    event ContainerCreated(address indexed owner, uint256 indexed dockId, address container, address[] initialModules);

    /// @notice Emitted when the ownership of a {Container} is transferred to a new owner
    /// @param container The address of the {Container}
    /// @param oldOwner The address of the current owner
    /// @param newOwner The address of the new owner
    event ContainerOwnershipTransferred(address indexed container, address oldOwner, address newOwner);

    /// @notice Emitted when the ownership of a {Dock} is transferred to a new owner
    /// @param dockId The address of the {Dock}
    /// @param oldOwner The address of the current owner
    /// @param newOwner The address of the new owner
    event DockOwnershipTransferred(uint256 indexed dockId, address oldOwner, address newOwner);

    /// @notice Emitted when the {ModuleKeeper} address is updated
    /// @param newModuleKeeper The new address of the {ModuleKeeper}
    event ModuleKeeperUpdated(IModuleKeeper newModuleKeeper);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the {ModuleKeeper} contract
    function moduleKeeper() external view returns (ModuleKeeper);

    /// @notice Retrieves the owner of the given dock ID
    function ownerOfDock(uint256 dockId) external view returns (address);

    /// @notice Retrieves the dock ID of the given container address
    function dockIdOfContainer(address container) external view returns (uint256);

    /// @notice Retrieves the owner address of the {Container}'s address
    function ownerOfContainer(address container) external view returns (address);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new {Container} contract and attaches it to a dock
    ///
    /// Notes:
    /// - if `dockId` equal zero, a new dock will be created
    ///
    /// Requirements:
    /// - `msg.sender` MUST be the dock owner if a new container is to be attached to an existing dock
    ///
    /// @param dockId The ID of the dock to attach the {Container} to
    /// @param initialModules Array of initially enabled modules
    /*     function createContainer(uint256 dockId, address[] memory initialModules) external returns (address container);
    */
    /// @notice Transfers the ownership of the `container` container
    ///
    /// Requirements:
    /// - reverts if `msg.sender` is not the current {Container} owner
    /// - reverts if `newOwner` is the zero-address
    ///
    /// @param container The address of the {Container} instance whose ownership is to be transferred
    /// @param newOwner The address of the new owner
    function transferContainerOwnership(address container, address newOwner) external;

    /// @notice Transfers the ownership of the `dockId` dock
    ///
    /// Notes:
    /// - does not check for zero-address; ownership will be renounced if `newOwner` is the zero-address
    ///
    /// Requirements:
    /// - `msg.sender` MUST be the current dock owner
    ///
    /// @param dockId The ID of the dock of whose ownership is to be transferred
    /// @param newOwner The address of the new owner
    function transferDockOwnership(uint256 dockId, address newOwner) external;

    /// @notice Updates the address of the {ModuleKeeper}
    ///
    /// Notes:
    /// - does not check for zero-address;
    ///
    /// Requirements:
    /// - reverts if `msg.sender` is not the {DockRegistry} owner
    ///
    /// @param newModuleKeeper The new address of the {ModuleKeeper}
    function updateModuleKeeper(ModuleKeeper newModuleKeeper) external;
}
