// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Space } from "./../Space.sol";
import { IModuleKeeper } from "./IModuleKeeper.sol";
import { ModuleKeeper } from "./../ModuleKeeper.sol";

/// @title IDockRegistry
/// @notice Contract that provides functionalities to create docks and deploy {Space}s from a single place
interface IDockRegistry {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new {Space} contract gets deployed
    /// @param owner The address of the owner
    /// @param dockId The ID of the dock to which this {Space} belongs
    /// @param space The address of the {Space}
    /// @param initialModules Array of initially enabled modules
    event SpaceCreated(address indexed owner, uint256 indexed dockId, address space, address[] initialModules);

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

    /// @notice Retrieves the dock ID of the given space address
    function dockIdOfSpace(address space) external view returns (uint256);

    /// @notice Retrieves the total number of accounts created by the `signer` address
    function totalAccountsOfSigner(address signer) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new {Space} contract and attaches it to a dock
    ///
    /// Notes:
    /// - if `dockId` equal zero, a new dock will be created
    ///
    /// Requirements:
    /// - `msg.sender` MUST be the dock owner if a new space is to be attached to an existing dock
    ///
    /// @param _admin The ID of the dock to attach the {Space} to
    /// @param _data Array of initially enabled modules
    function createAccount(address _admin, bytes calldata _data) external returns (address space);

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
