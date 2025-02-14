// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IModuleKeeper } from "./interfaces/IModuleKeeper.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title ModuleKeeper
/// @notice See the documentation in {IModuleKeeper}
contract ModuleKeeper is IModuleKeeper, Ownable {
    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleKeeper
    mapping(address module => bool) public override isAllowlisted;

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the initial owner of the {ModuleKeeper}
    constructor(address _initialOwner) Ownable(_initialOwner) { }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleKeeper
    function addToAllowlist(address[] calldata modules) public onlyOwner {
        for (uint256 i; i < modules.length; ++i) {
            // Effects: add the module to the allowlist
            _allowlistModule(modules[i]);
        }

        // Log the modules allowlisting
        emit ModulesAllowlisted(owner, modules);
    }

    /// @inheritdoc IModuleKeeper
    function removeFromAllowlist(address[] calldata modules) public onlyOwner {
        for (uint256 i; i < modules.length; ++i) {
            // Effects: remove the module from the allowlist
            isAllowlisted[modules[i]] = false;
        }

        // Log the modules removal from the allowlist
        emit ModulesRemovedFromAllowlist(owner, modules);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Adds the `module` module to the allowlist
    function _allowlistModule(address module) internal {
        // Check: the module has a valid non-zero code size
        if (module.code.length == 0) {
            revert Errors.InvalidZeroCodeModule();
        }

        // Effects: add the module to the allowlist
        isAllowlisted[module] = true;
    }
}
