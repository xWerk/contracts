// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

import { FlowStreamManager } from "./sablier-flow/FlowStreamManager.sol";
import { ICompensationModule } from "./interfaces/ICompensationModule.sol";
import { Types } from "./libraries/Types.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title CompensationModule
/// @notice See the documentation in {ICompensationModule}
contract CompensationModule is ICompensationModule, FlowStreamManager, UUPSUpgradeable {
    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "1.0.0";
    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.CompensationModule
    struct CompensationModuleStorage {
        /// @notice Compensation components details mapped by the component ID
        mapping(uint256 id => Types.CompensationComponent) components;
        /// @notice Counter to keep track of the next ID used to create a new compensation component
        uint256 nextComponentId;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.CompensationModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMPENSATION_MODULE_STORAGE_LOCATION =
        0x267484be310ddc11d8a2bbbf514e29e1cab2b3d768542b45e869f920f4b7a300;

    /// @dev Retrieves the storage of the {CompensationModule} contract
    function _getComponentModuleStorage() internal pure returns (CompensationModuleStorage storage $) {
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
        CompensationModuleStorage storage $ = _getComponentModuleStorage();

        // Start the first compensation request ID from 1
        $.nextComponentId = 1;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                MODIFIERS & CHECKS
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

    /// @dev Checks that `componentId` does not reference a null compensation component
    ///
    /// Notes:
    /// - A private function is used instead of a modifier to avoid two redundant SLOAD operations,
    /// in a scenario where the storage layout is accessed in both the modifier and the function that
    /// uses the modifier. As a result, the overall gas cost is reduced because an SLOAD followed by a
    /// JUMP is cheaper than performing two separate SLOADs.
    function _notNullComponent(uint256 componentId) internal view returns (CompensationModuleStorage storage $) {
        // Retrieve the storage of the {CompensationModule} contract
        $ = _getComponentModuleStorage();

        // Checks: the compensation component exists
        if ($.components[componentId].streamId == 0) {
            revert Errors.ComponentNull();
        }
    }

    /// @dev Checks that `msg.sender` is the compensation component sender
    function _onlyComponentSender(address componentSender) internal view {
        // Checks: `msg.sender` is the component sender
        if (componentSender != msg.sender) revert Errors.OnlyComponentSender();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICompensationModule
    function getComponent(uint256 componentId) external view returns (Types.CompensationComponent memory component) {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Return the component fields
        return $.components[componentId];
    }

    /// @inheritdoc ICompensationModule
    function getComponentStream(uint256 streamId) external view returns (Flow.Stream memory stream) {
        return _getStream(streamId);
    }

    /// @inheritdoc ICompensationModule
    function statusOfComponent(uint256 componentId) external view returns (Flow.Status status) {
        // Checks: the compensation component is not null then cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Return the status of the compensation component stream
        return statusOf($.components[componentId].streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICompensationModule
    function createComponent(
        address recipient,
        UD21x18 ratePerSecond,
        Types.ComponentType componentType,
        IERC20 asset
    )
        external
        onlySpace
        returns (uint256 componentId, uint256 streamId)
    {
        // Checks: the recipient is not the zero address
        if (recipient == address(0)) revert Errors.InvalidZeroAddressRecipient();

        // Checks, Effects, Interactions: create the compensation component
        (componentId, streamId) = _createComponent(recipient, ratePerSecond, componentType, asset);

        // Log the compensation creation
        emit ComponentCreated(componentId, recipient, streamId);
    }

    /// @inheritdoc ICompensationModule
    function adjustComponentRatePerSecond(uint256 componentId, UD21x18 newRatePerSecond) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in storage to update its rate per second
        Types.CompensationComponent storage component = $.components[componentId];

        // Checks: `msg.sender` is the component sender
        _onlyComponentSender(component.sender);

        // Checks: the new rate per second is not zero
        if (newRatePerSecond.unwrap() == 0) revert Errors.InvalidZeroRatePerSecond();

        // Retrieve the stream ID of the compensation component
        uint256 streamId = component.streamId;

        // Effects: update the compensation component rate per second
        component.ratePerSecond = newRatePerSecond;

        // Checks, Effects, Interactions: adjust the compensation component stream rate per second
        _adjustStreamRatePerSecond(streamId, newRatePerSecond);

        // Log the compensation component rate per second adjustment
        emit ComponentRatePerSecondAdjusted(componentId, newRatePerSecond);
    }

    /// @inheritdoc ICompensationModule
    function depositToComponent(uint256 componentId, uint128 amount) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Checks: the deposit amount is not zero
        if (amount == 0) revert Errors.InvalidZeroDepositAmount();

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks, Effects, Interactions: deposit the amount to the compensation component stream
        _depositToStream({
            streamId: component.streamId,
            asset: component.asset,
            amount: amount,
            recipient: component.recipient
        });

        // Log the compensation component deposit
        emit ComponentDeposited(componentId, amount);
    }

    /// @inheritdoc ICompensationModule
    function withdrawFromComponent(uint256 componentId) external returns (uint128 withdrawnAmount) {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks: `msg.sender` is the compensation recipient
        if (component.recipient != msg.sender) revert Errors.OnlyComponentRecipient();

        // Checks, Effects, Interactions: withdraw the amount from the compensation component stream
        withdrawnAmount = _withdrawMaxFromStream({ streamId: component.streamId, to: msg.sender });

        // Log the compensation component stream withdrawal
        emit ComponentWithdrawn(componentId, withdrawnAmount);
    }

    /// @inheritdoc ICompensationModule
    function pauseComponent(uint256 componentId) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks: `msg.sender` is the component sender
        _onlyComponentSender(component.sender);

        // Checks, Effects, Interactions: pause the compensation component stream
        _pauseStream(component.streamId);

        // Log the compensation component stream pause
        emit ComponentPaused(componentId);
    }

    /// @inheritdoc ICompensationModule
    function restartComponent(uint256 componentId, UD21x18 newRatePerSecond) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks: `msg.sender` is the component sender
        _onlyComponentSender(component.sender);

        // Checks: the new rate per second is not zero
        if (newRatePerSecond.unwrap() == 0) revert Errors.InvalidZeroRatePerSecond();

        // Checks, Effects, Interactions: restart the compensation component stream with a new rate per second
        _restartStream(component.streamId, newRatePerSecond);

        // Log the compensation component stream restart
        emit ComponentRestarted(componentId, newRatePerSecond);
    }

    /// @inheritdoc ICompensationModule
    function cancelComponent(uint256 componentId) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks: `msg.sender` is the component sender
        _onlyComponentSender(component.sender);

        // Checks, Effects, Interactions: cancel the compensation component stream
        _cancelStream(component.streamId);

        // Log the compensation component stream cancellation
        emit ComponentCancelled(componentId);
    }

    /// @inheritdoc ICompensationModule
    function refundComponent(uint256 componentId) external {
        // Checks: if the compensation component is not null, cache the storage pointer
        CompensationModuleStorage storage $ = _notNullComponent(componentId);

        // Load the component in memory
        Types.CompensationComponent memory component = $.components[componentId];

        // Checks: `msg.sender` is the component sender
        _onlyComponentSender(component.sender);

        // Checks, Effects, Interactions: refund the compensation component stream
        _refundStream(component.streamId);

        // Log the compensation component stream refund
        emit ComponentRefunded(componentId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                           INTERNAL NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev See the documentation for the user-facing functions that call this internal function
    function _createComponent(
        address recipient,
        UD21x18 ratePerSecond,
        Types.ComponentType componentType,
        IERC20 asset
    )
        internal
        returns (uint256 componentId, uint256 streamId)
    {
        // Retrieve the contract storage
        CompensationModuleStorage storage $ = _getComponentModuleStorage();

        // Cache the next component ID
        componentId = $.nextComponentId;

        // Checks: the compensation component rate per second is not zero
        if (ratePerSecond.unwrap() == 0) revert Errors.InvalidZeroRatePerSecond();

        // Checks, Effects, Interactions: create the Sablier Flow stream
        streamId = _createStream(recipient, ratePerSecond, asset);

        // Effects: create the compensation component
        $.components[componentId] = Types.CompensationComponent({
            sender: msg.sender,
            ratePerSecond: ratePerSecond,
            componentType: componentType,
            recipient: recipient,
            asset: asset,
            streamId: streamId
        });

        // Effects: increment the next compensation ID
        // Use unchecked because the compensation ID cannot realistically overflow
        unchecked {
            $.nextComponentId++;
        }
    }
}
