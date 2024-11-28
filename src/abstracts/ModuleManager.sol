// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IModuleManager } from "./../interfaces/IModuleManager.sol";
import { ModuleKeeper } from "./../ModuleKeeper.sol";
import { Errors } from "./../libraries/Errors.sol";

/// @title ModuleManager
/// @notice See the documentation in {IModuleManager}
abstract contract ModuleManager is IModuleManager {
    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleManager
    mapping(address module => bool) public override isModuleEnabled;

    /*//////////////////////////////////////////////////////////////////////////
                                    INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the initial module(s) enabled on the space
    function _initializeModuleManager(ModuleKeeper moduleKeeper, address[] memory _initialModules) internal {
        // Effects: enable the smart account itself as a module to allow self-execution
        isModuleEnabled[address(this)] = true;

        // Effects: enable the initial module(s)
        _enableBatchModules(moduleKeeper, _initialModules);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleManager
    function enableModule(address module) public virtual;

    /// @inheritdoc IModuleManager
    function disableModule(address module) public virtual;

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Reverts if the `module` module is not enabled on the space
    function _checkIfModuleIsEnabled(address module) internal view {
        if (!isModuleEnabled[module]) {
            revert Errors.ModuleNotEnabled(module);
        }
    }

    /// @dev Enables multiple modules at the same time
    function _enableBatchModules(ModuleKeeper moduleKeeper, address[] memory modules) internal {
        for (uint256 i; i < modules.length; ++i) {
            _enableModule(moduleKeeper, modules[i]);
        }
    }

    /// @dev Enables one single module at a time
    function _enableModule(ModuleKeeper moduleKeeper, address module) internal {
        // Checks: module is in the allowlist
        if (!moduleKeeper.isAllowlisted(module)) {
            revert Errors.ModuleNotAllowlisted();
        }

        // Effects: enable the module
        isModuleEnabled[module] = true;

        // Log the module enablement
        emit ModuleEnabled({ module: module, owner: msg.sender });
    }

    /// @dev Disables one single module at a time
    function _disableModule(address module) internal {
        // Effects: disable the module
        isModuleEnabled[module] = false;

        // Log the module disablement
        emit ModuleDisabled({ module: module, owner: msg.sender });
    }
}
