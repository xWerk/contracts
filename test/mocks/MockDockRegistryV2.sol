// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IDockRegistry } from "./../../src/interfaces/IDockRegistry.sol";
import { Space } from "./../../src/Space.sol";
import { ModuleKeeper } from "./../../src/ModuleKeeper.sol";

/// @title MockDockRegistryV2
/// @notice See the documentation in {IDockRegistry}
contract MockDockRegistryV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    ModuleKeeper public moduleKeeper;

    mapping(uint256 dockId => address owner) public ownerOfDock;

    mapping(address space => uint256 dockId) public dockIdOfSpace;

    mapping(address space => address owner) public ownerOfWorkspace;

    /// @dev Counter to keep track of the next dock ID
    uint256 private _dockNextId;

    /*//////////////////////////////////////////////////////////////////////////
                                   RESERVED STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[45] private __gap;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Lock the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the address of the {ModuleKeeper} contract, registry owner and sets the next dock ID to start from 1
    function initialize(address _initialOwner, ModuleKeeper _moduleKeeper) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        _dockNextId = 1;
        moduleKeeper = _moduleKeeper;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
