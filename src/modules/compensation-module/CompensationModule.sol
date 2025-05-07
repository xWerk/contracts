// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ICompensationModule } from "./interfaces/ICompensationModule.sol";
import { Types } from "./libraries/Types.sol";
import { FlowStreamManager } from "./sablier-flow/FlowStreamManager.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Errors } from "./libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

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
        uint256 nextCompensationPlanId;
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
        $.nextCompensationPlanId = 1;
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

    /// @dev Checks that `compensationPlanId` does not reference a null compensation plan
    ///
    /// Notes:
    /// - A private function is used instead of a modifier to avoid two redundant SLOAD operations,
    /// in a scenario where the storage layout is accessed in both the modifier and the function that
    /// uses the modifier. As a result, the overall gas cost is reduced because an SLOAD followed by a
    /// JUMP is cheaper than performing two separate SLOADs.
    function _notNullPlan(uint256 compensationPlanId) internal view returns (CompensationModuleStorage storage $) {
        // Retrieve the storage of the {CompensationModule} contract
        $ = _getCompensationModuleStorage();

        // Checks: the compensation plan exists
        if ($.compensations[compensationPlanId].sender == address(0)) {
            revert Errors.CompensationPlanNull();
        }
    }

    /// @dev Checks that `componentId` does not reference a null compensation component
    ///
    /// Notes:
    /// - If the `compensationPlanId` does not exist, the component will also be null
    /// - A private function is used instead of a modifier to avoid two redundant SLOAD operations,
    /// in a scenario where the storage layout is accessed in both the modifier and the function that
    /// uses the modifier. As a result, the overall gas cost is reduced because an SLOAD followed by a
    /// JUMP is cheaper than performing two separate SLOADs.
    function _notNullComponent(
        uint256 compensationPlanId,
        uint96 componentId
    )
        internal
        view
        returns (CompensationModuleStorage storage $)
    {
        // Retrieve the storage of the {CompensationModule} contract
        $ = _getCompensationModuleStorage();

        // Checks: the compensation component exists
        if ($.compensations[compensationPlanId].components[componentId].streamId == 0) {
            revert Errors.CompensationComponentNull();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICompensationModule
    function getCompensationPlan(uint256 compensationPlanId)
        external
        view
        returns (address sender, address recipient, uint96 numberOfComponents, Types.Component[] memory components)
    {
        // Checks: the compensation plan is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullPlan(compensationPlanId);

        // Get the compensation plan
        Types.Compensation storage plan = $.compensations[compensationPlanId];

        // Get the components
        components = new Types.Component[](plan.nextComponentId);
        for (uint256 i; i < components.length; ++i) {
            components[i] = plan.components[i];
        }

        // Return the compensation plan fields
        return (plan.sender, plan.recipient, plan.nextComponentId, components);
    }

    /// @inheritdoc ICompensationModule
    function getComponent(
        uint256 compensationPlanId,
        uint96 componentId
    )
        external
        view
        returns (Types.Component memory)
    {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Return the compensation component
        return $.compensations[compensationPlanId].components[componentId];
    }

    /// @inheritdoc ICompensationModule
    function getComponentStream(uint256 streamId) external view returns (Flow.Stream memory stream) {
        return _getStream(streamId);
    }

    /// @inheritdoc ICompensationModule
    function statusOfComponent(
        uint256 compensationPlanId,
        uint96 componentId
    )
        external
        view
        returns (Flow.Status status)
    {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Return the status of the compensation component stream
        return statusOfComponentStream($.compensations[compensationPlanId].components[componentId].streamId);
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
            // Checks: the recipient is not the zero address
            if (recipients[i] == address(0)) revert Errors.InvalidZeroAddressRecipient();

            // Checks: the components array is not empty
            if (components[i].length == 0) revert Errors.InvalidEmptyComponentsArray();

            // Checks, Effects, Interactions: create the compensation plan for the current recipient
            _createCompensationPlan($, recipients[i], components[i]);
        }
    }

    /// @inheritdoc ICompensationModule
    function adjustComponentRatePerSecond(
        uint256 compensationPlanId,
        uint96 componentId,
        UD21x18 newRatePerSecond
    )
        external
    {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks: `msg.sender` is the compensation plan sender
        if (compensationPlan.sender != msg.sender) revert Errors.OnlyCompensationPlanSender();

        // Checks: the new rate per second is not zero
        if (newRatePerSecond.unwrap() == 0) revert Errors.InvalidZeroRatePerSecond();

        // Retrieve the stream ID of the compensation plan component
        uint256 streamId = compensationPlan.components[componentId].streamId;

        // Effects: update the compensation component rate per second
        compensationPlan.components[componentId].ratePerSecond = newRatePerSecond;

        // Checks, Effects, Interactions: adjust the compensation component stream rate per second
        _adjustComponentStreamRatePerSecond(streamId, newRatePerSecond);

        // Log the compensation component rate per second adjustment
        emit ComponentRatePerSecondAdjusted(compensationPlanId, componentId, newRatePerSecond);
    }

    /// @inheritdoc ICompensationModule
    function depositToComponent(uint256 compensationPlanId, uint96 componentId, uint128 amount) external {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Checks: the deposit amount is not zero
        if (amount == 0) revert Errors.InvalidZeroDepositAmount();

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks, Effects, Interactions: deposit the amount to the compensation component stream
        _depositToComponentStream({
            streamId: compensationPlan.components[componentId].streamId,
            asset: compensationPlan.components[componentId].asset,
            amount: amount,
            recipient: compensationPlan.recipient
        });

        // Log the compensation component deposit
        emit CompensationComponentDeposited(compensationPlanId, componentId, amount);
    }

    /// @inheritdoc ICompensationModule
    function withdrawFromComponent(
        uint256 compensationPlanId,
        uint96 componentId
    )
        external
        returns (uint128 withdrawnAmount)
    {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks: `msg.sender` is the compensation plan recipient
        if (compensationPlan.recipient != msg.sender) revert Errors.OnlyCompensationPlanRecipient();

        // Checks, Effects, Interactions: withdraw the amount from the compensation component stream
        withdrawnAmount = _withdrawMaxFromComponentStream({
            streamId: compensationPlan.components[componentId].streamId,
            to: msg.sender
        });

        // Log the compensation component stream withdrawal
        emit CompensationComponentWithdrawn(compensationPlanId, componentId, withdrawnAmount);
    }

    /// @inheritdoc ICompensationModule
    function pauseComponent(uint256 compensationPlanId, uint96 componentId) external {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks: `msg.sender` is the compensation plan sender
        if (compensationPlan.sender != msg.sender) revert Errors.OnlyCompensationPlanSender();

        // Checks, Effects, Interactions: pause the compensation component stream
        _pauseComponentStream(compensationPlan.components[componentId].streamId);

        // Log the compensation component stream pause
        emit CompensationComponentPaused(compensationPlanId, componentId);
    }

    /// @inheritdoc ICompensationModule
    function cancelComponent(uint256 compensationPlanId, uint96 componentId) external {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks: `msg.sender` is the compensation plan sender
        if (compensationPlan.sender != msg.sender) revert Errors.OnlyCompensationPlanSender();

        // Checks, Effects, Interactions: cancel the compensation component stream
        _cancelComponentStream(compensationPlan.components[componentId].streamId);

        // Log the compensation component stream cancellation
        emit CompensationComponentCancelled(compensationPlanId, componentId);
    }

    /// @inheritdoc ICompensationModule
    function refundComponent(uint256 compensationPlanId, uint96 componentId) external {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(compensationPlanId, componentId);

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Checks: `msg.sender` is the compensation plan sender
        if (compensationPlan.sender != msg.sender) revert Errors.OnlyCompensationPlanSender();

        // Checks, Effects, Interactions: refund the compensation component stream
        _refundComponentStream(compensationPlan.components[componentId].streamId);

        // Log the compensation component stream refund
        emit CompensationComponentRefunded(compensationPlanId, componentId);
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
        compensationPlanId = $.nextCompensationPlanId;

        // Cache the compensation plan details to save on multiple storage reads
        Types.Compensation storage compensationPlan = $.compensations[compensationPlanId];

        // Cache the components length to save on gas costs
        uint256 componentsLength = components.length;

        // Create the compensation components
        for (uint256 i; i < componentsLength; ++i) {
            // Checks: the compensation component rate per second is not zero
            if (components[i].ratePerSecond.unwrap() == 0) revert Errors.InvalidZeroRatePerSecond();

            // Checks, Effects, Interactions: create the flow stream
            uint256 streamId = _createComponentStream(recipient, components[i]);

            // Effects: set the compensation component stream ID
            components[i].streamId = streamId;

            // Get the next compensation component ID
            uint96 componentId = compensationPlan.nextComponentId;

            // Effects: add the compensation component to the compensation plan
            compensationPlan.components[componentId] = components[i];

            // Effects: increment the next compensation component ID
            // Use unchecked because the compensation component ID cannot realistically overflow
            unchecked {
                compensationPlan.nextComponentId++;
            }
        }

        // Effects: set the recipient address of the current compensation plan
        compensationPlan.recipient = recipient;

        // Effects: set the sender address of the current compensation plan
        compensationPlan.sender = msg.sender;

        // Effects: increment the next compensation ID
        // Use unchecked because the compensation ID cannot realistically overflow
        unchecked {
            $.nextCompensationPlanId++;
        }

        // Log the compensation plan creation
        emit CompensationPlanCreated(compensationPlanId, recipient);
    }
}
