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
    /// @param module The address of the module to be allowlisted
    event ModuleAllowlisted(address indexed owner, address indexed module);

    /// @notice Emitted when a module is removed from the allowlist
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param module The address of the module to be removed
    event ModuleRemovedFromAllowlist(address indexed owner, address indexed module);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks if the `module` module is allowlisted to be used by a {Space}
    /// @param module The address of the module contract
    function isAllowlisted(address module) external view returns (bool allowlisted);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds the `module` module to the allowlist
    /// @param module The address of the module to be allowlisted
    function addToAllowlist(address module) external;

    /// @notice Removes the `module` module from the allowlist
    /// @param module The address of the module to remove
    function removeFromAllowlist(address module) external;
}
