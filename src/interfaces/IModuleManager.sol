// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { DockRegistry } from "./../DockRegistry.sol";

/// @title IModuleManager
/// @notice Contract that provides functionalities to manage multiple modules within a {Container} contract
interface IModuleManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a module is enabled on the container
    /// @param module The address of the enabled module
    event ModuleEnabled(address indexed module, address indexed owner);

    /// @notice Emitted when a module is disabled on the container
    /// @param module The address of the disabled module
    event ModuleDisabled(address indexed module, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the {DockRegistry} contract
    /*     function dockRegistry() external view returns (DockRegistry);
    */
    /// @notice Checks whether the `module` module is enabled on the container
    function isModuleEnabled(address module) external view returns (bool isEnabled);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enables the `module` module on the {ModuleManager} contract
    /// @param module The address of the module to enable
    function enableModule(address module) external;

    /// @notice Disables the `module` module on the {ModuleManager} contract
    /// @param module The address of the module to disable
    function disableModule(address module) external;
}
