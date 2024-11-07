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
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModuleKeeper
    function addToAllowlist(address module) public onlyOwner {
        // Check: the module has a valid non-zero code size
        if (module.code.length == 0) {
            revert Errors.InvalidZeroCodeModule();
        }

        // Effects: add the module to the allowlist
        isAllowlisted[module] = true;

        // Log the module allowlisting
        emit ModuleAllowlisted(owner, module);
    }

    /// @inheritdoc IModuleKeeper
    function removeFromAllowlist(address module) public onlyOwner {
        // Effects: remove the module from the allowlist
        isAllowlisted[module] = false;

        // Log the module removal from the allowlist
        emit ModuleRemovedFromAllowlist(owner, module);
    }
}
