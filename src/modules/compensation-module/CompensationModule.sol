// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ICompensationModule } from "./interfaces/ICompensationModule.sol";
import { Types } from "./libraries/Types.sol";
import { FlowStreamManager } from "./sablier-flow/FlowStreamManager.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";

/// @title CompensationModule
/// @notice See the documentation in {ICompensationModule}
contract CompensationModule is ICompensationModule, FlowStreamManager, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.CompensationModule
    struct CompensationModuleStorage {
        /// @notice Compensation details mapped by the `id` compensation ID
        mapping(uint256 id => Types.Compensation) compensations;
        /// @notice Counter to keep track of the next ID used to create a new compensation
        uint256 nextCompensationId;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.CompensationModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMPENSATION_MODULE_STORAGE_LOCATION =
        0x267484be310ddc11d8a2bbbf514e29e1cab2b3d768542b45e869f920f4b7a300;

    /// @dev Retrieves the storage of the {CompensationModule} contract
    function _getCompensationModuleStorage() internal pure returns (CompensationModuleStorage storage $) {
        assembly {
            $.slot := COMPENSATION_MODULE_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the proxy and the {Ownable} contract
    function initialize(
        ISablierFlow _sablierFlow,
        address _initialOwner,
        address _brokerAccount,
        UD60x18 _brokerFee
    )
        public
        initializer
    {
        __FlowStreamManager_init(_sablierFlow, _initialOwner, _brokerAccount, _brokerFee);
        __UUPSUpgradeable_init();

        // Retrieve the contract storage
        CompensationModuleStorage storage $ = _getCompensationModuleStorage();

        // Start the first compensation request ID from 1
        $.nextCompensationId = 1;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
