// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IModuleKeeper
/// @notice Contract responsible for managing an allowlist-based mapping with "safe to use" {Module} contracts
interface IModuleKeeper {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new module is allowlisted
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param modules The addresses of the modules to be allowlisted
    event ModulesAllowlisted(address indexed owner, address[] modules);

    /// @notice Emitted when a module is removed from the allowlist
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param modules The addresses of the modules to be removed
    event ModulesRemovedFromAllowlist(address indexed owner, address[] modules);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks if the `module` module is allowlisted to be used by a {Space}
    /// @param module The address of the module contract
    function isAllowlisted(address module) external view returns (bool allowlisted);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds the `modules` modules to the allowlist
    ///
    /// Requirements:
    /// - each `module` in `modules` must have a valid non-zero code size
    /// - `msg.sender` must be the owner of the {ModuleKeeper}
    ///
    /// @param modules The addresses of the modules to be allowlisted
    function addToAllowlist(address[] calldata modules) external;

    /// @notice Removes the `modules` modules from the allowlist
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner of the {ModuleKeeper}
    ///
    /// @param modules The addresses of the modules to be removed
    function removeFromAllowlist(address[] calldata modules) external;
}
