// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IModuleManager } from "./interfaces/IModuleManager.sol";

/// @title ModuleManager
/// @notice See the documentation in {IModuleManager}
contract ModuleManager is IModuleManager {
    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleManager
    mapping(address module => bool) public override isModuleEnabled;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the `_initialModules` initial module(s) enabled on a container
    constructor(address[] memory _initialModules) {
        _enableBatchModules(_initialModules);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleManager
    function enableModule(address module) public virtual {
        isModuleEnabled[module] = true;

        emit ModuleEnabled({ module: module });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enables multiple modules at the same time
    function _enableBatchModules(address[] memory modules) internal {
        for (uint256 i; i < modules.length; ++i) {
            enableModule(modules[i]);
        }
    }
}
