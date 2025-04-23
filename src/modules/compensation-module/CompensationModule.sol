// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ICompensationModule } from "./interfaces/ICompensationModule.sol";
import { Types } from "./libraries/Types.sol";
import { FlowStreamManager } from "./sablier-flow/FlowStreamManager.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title CompensationModule
/// @notice See the documentation in {ICompensationModule}
contract CompensationModule is ICompensationModule, FlowStreamManager, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.CompensationModule
    struct CompensationModuleStorage {
        /// @notice Compensation details mapped by the compensation ID
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

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        // Checks: the sender is a valid non-zero code size contract
        if (msg.sender.code.length == 0) {
            revert Errors.SpaceZeroCodeSize();
        }

        // Checks: the sender implements the ERC-165 interface required by {ISpace}
        bytes4 interfaceId = type(ISpace).interfaceId;
        if (!ISpace(msg.sender).supportsInterface(interfaceId)) revert Errors.SpaceUnsupportedInterface();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICompensationModule
    function createCompensationPlan(
        address recipient,
        Types.Component[] memory components
    )
        external
        onlySpace
        returns (uint256 compensationPlanId)
    {
        // Checks: the recipient is not the zero address
        if (recipient == address(0)) revert Errors.InvalidZeroAddressRecipient();

        // Checks: the compensation components array is not empty
        if (components.length == 0) revert Errors.InvalidEmptyComponentsArray();

        // Retrieve the contract storage
        CompensationModuleStorage storage $ = _getCompensationModuleStorage();

        // Checks, Effects, Interactions: create the compensation plan
        compensationPlanId = _createCompensationPlan($, recipient, components);
    }

    /// @inheritdoc ICompensationModule
    function createBatchCompensationPlan(
        address[] memory recipients,
        Types.Component[][] memory components
    )
        external
        onlySpace
    {
        // Cache the recipients length to save on gas costs
        uint256 recipientsLength = recipients.length;

        // Checks: the recipients array is not empty
        if (recipientsLength == 0) revert Errors.InvalidEmptyRecipientsArray();

        // Checks: the recipients and components arrays have the same length
        if (recipientsLength != components.length) revert Errors.InvalidRecipientsAndComponentsArraysLength();

        // Retrieve the contract storage
        CompensationModuleStorage storage $ = _getCompensationModuleStorage();

        for (uint256 i; i < recipientsLength; ++i) {
            // Checks: the components array is not empty
            if (components[i].length == 0) revert Errors.InvalidEmptyComponentsArray();

            // Checks, Effects, Interactions: create the compensation plan for the current recipient
            _createCompensationPlan($, recipients[i], components[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                           INTERNAL NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev See the documentation for the user-facing functions that call this internal function
    function _createCompensationPlan(
        CompensationModuleStorage storage $,
        address recipient,
        Types.Component[] memory components
    )
        internal
        returns (uint256 compensationPlanId)
    {
        // Get the next compensation plan ID
        compensationPlanId = $.nextCompensationId;

        // Effects: set the recipient address of the current compensation plan
        $.compensations[compensationPlanId].recipient = recipient;

        // Cache the components length to save on gas costs
        uint256 componentsLength = components.length;

        // Create the compensation components
        for (uint256 i; i < componentsLength; ++i) {
            // Checks, Effects, Interactions: create the flow stream
            uint256 streamId = this.createFlowStream(recipient, components[i]);

            // Effects: set the compensation component stream ID
            components[i].streamId = streamId;

            // Get the next compensation component ID
            uint96 componentId = $.compensations[compensationPlanId].nextComponentId;

            // Effects: add the compensation component to the compensation
            $.compensations[compensationPlanId].components[componentId] = components[i];

            // Effects: increment the next compensation component ID
            // Use unchecked because the compensation component ID cannot realistically overflow
            unchecked {
                $.compensations[compensationPlanId].nextComponentId++;
            }
        }

        // Effects: increment the next compensation ID
        // Use unchecked because the compensation ID cannot realistically overflow
        unchecked {
            $.nextCompensationId++;
        }

        // Log the compensation plan creation
        emit CompensationPlanCreated(compensationPlanId, recipient);
    }
}
