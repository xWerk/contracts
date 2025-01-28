// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IModuleManager
/// @notice Contract that provides functionalities to manage multiple modules within a {Space} contract
interface IModuleManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a module is enabled on the space
    /// @param module The address of the enabled module
    event ModuleEnabled(address indexed module, address indexed owner);

    /// @notice Emitted when a module is disabled on the space
    /// @param module The address of the disabled module
    event ModuleDisabled(address indexed module, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `module` module is enabled on the space
    function isModuleEnabled(address module) external view returns (bool isEnabled);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enables one or multiple `modules` modules on the {ModuleManager} contract
    /// @param modules The array with addresses of the module to enable
    function enableModules(address[] memory modules) external;

    /// @notice Disables one or multiple `modules` modules on the {ModuleManager} contract
    /// @param modules The array with addresses of the modules to disable
    function disableModules(address[] memory modules) external;
}
