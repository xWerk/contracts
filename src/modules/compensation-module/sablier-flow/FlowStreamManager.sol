// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Broker, Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IFlowStreamManager } from "./interfaces/IFlowStreamManager.sol";
import { Types } from "../libraries/Types.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FlowStreamManager
/// @notice See the documentation in {IFlowStreamManager}
contract FlowStreamManager is IFlowStreamManager, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.FlowStreamManager
    struct FlowStreamManagerStorage {
        /// @notice The Sablier Flow contract address
        ISablierFlow SABLIER_FLOW;
        /// @notice Stores the initial address of the account that started the stream
        /// By default, each stream will be created by this contract (the sender address of each stream will be address(this))
        /// therefore this mapping is used to allow only authorized senders to execute management-related actions i.e. cancellations
        mapping(uint256 streamId => address initialSender) initialStreamSender;
        /// @notice The broker parameters charged to create Sablier Flow streams
        Broker broker;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.FlowStreamManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FLOW_STREAM_MANAGER_STORAGE_LOCATION =
        0x4d23eed36b31d0039e60f79007ec7a6b2c9226ee2c97b0667e422be6211dfa00;

    /// @dev Retrieves the storage of the {FlowStreamManager} contract
    function _getFlowStreamManagerStorage() internal pure returns (FlowStreamManagerStorage storage $) {
        assembly {
            $.slot := FLOW_STREAM_MANAGER_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the {FlowStreamManager} contract
    function __FlowStreamManager_init(
        ISablierFlow _sablierFlow,
        address _initialAdmin,
        address _brokerAccount,
        UD60x18 _brokerFee
    )
        internal
        onlyInitializing
    {
        __Ownable_init(_initialAdmin);

        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Set the Sablier Flow contract address
        $.SABLIER_FLOW = _sablierFlow;

        // Set the broker account and fee
        $.broker = Broker({ account: _brokerAccount, fee: _brokerFee });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlowStreamManager
    function broker() public view override returns (Broker memory brokerConfig) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Return the broker fee
        brokerConfig = $.broker;
    }

    /// @inheritdoc IFlowStreamManager
    function SABLIER_FLOW() public view override returns (ISablierFlow) {
        return _getFlowStreamManagerStorage().SABLIER_FLOW;
    }

    /// @inheritdoc IFlowStreamManager
    function statusOfComponentStream(uint256 streamId) public view returns (Flow.Status status) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Return the status of the stream
        return $.SABLIER_FLOW.statusOf(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlowStreamManager
    function updateStreamBrokerFee(UD60x18 newBrokerFee) public onlyOwner {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Log the broker fee update
        emit BrokerFeeUpdated({ oldFee: $.broker.fee, newFee: newBrokerFee });

        // Update the fee charged by the broker
        $.broker.fee = newBrokerFee;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SABLIER FLOW-SPECIFIC INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates a new Sablier flow stream without upfront deposit for a compensation component
    /// @dev See the documentation in {ISablierFlow-create}
    /// @param recipient The address of the recipient of the compensation component
    /// @param component The component of the compensation plan to be streamed
    /// @return streamId The ID of the newly created stream
    function _createComponentStream(
        address recipient,
        Types.Component memory component
    )
        internal
        returns (uint256 streamId)
    {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Create the flow stream using the `create` function
        streamId = $.SABLIER_FLOW.create({
            sender: address(this), // The sender will be able to pause the stream or change rate per second
            recipient: recipient, // The recipient of the streamed tokens
            ratePerSecond: component.ratePerSecond, // The rate per second of the stream
            token: component.asset, // The streaming token
            transferable: false // Whether the stream will be transferable or not
         });

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        $.initialStreamSender[streamId] = msg.sender;
    }

    /// @dev See the documentation in {ISablierFlow-adjustRatePerSecond}
    function _adjustComponentStreamRatePerSecond(uint256 streamId, UD21x18 newRatePerSecond) internal {
        FlowStreamManagerStorage storage $ = _onlyInitialStreamSender(streamId);

        // Adjust the rate per second of the stream
        $.SABLIER_FLOW.adjustRatePerSecond(streamId, newRatePerSecond);
    }

    /// @dev See the documentation in {ISablierFlow-deposit}
    ///
    /// Notes:
    /// - The `sender` is automatically set to the address of the {FlowStreamManager} contract and the access
    /// control is handled by the private `_onlyInitialStreamSender` function.
    function _depositToComponentStream(uint256 streamId, IERC20 asset, uint128 amount, address recipient) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier Flow contract to spend it
        _transferFromAndApprove({ asset: asset, amount: amount, spender: address($.SABLIER_FLOW) });

        // Deposit the amount to the stream
        $.SABLIER_FLOW.depositViaBroker({
            streamId: streamId,
            totalAmount: amount,
            sender: address(this),
            recipient: recipient,
            broker: $.broker
        });
    }

    /// @dev See the documentation in {ISablierFlow-withdrawMax}
    function _withdrawMaxFromComponentStream(uint256 streamId, address to) internal returns (uint128) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Withdraw the maximum amount from the stream
        (uint128 withdrawnAmount,) = $.SABLIER_FLOW.withdrawMax(streamId, to);

        // Return the withdrawn amount
        return withdrawnAmount;
    }

    /// @dev See the documentation in {ISablierFlow-pause}
    function _pauseComponentStream(uint256 streamId) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Checks: the `msg.sender` is the initial stream creator
        address initialSender = $.initialStreamSender[streamId];
        if (msg.sender != initialSender) revert Errors.OnlyInitialStreamSender(initialSender);

        // Pause the stream
        $.SABLIER_FLOW.pause(streamId);
    }

    /// @dev Cancels a compensation component stream by forfeiting its uncovered debt (if any) and marking it as voided
    /// See the documentation in {ISablierFlow-void}
    function _cancelComponentStream(uint256 streamId) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Cancel the stream
        $.SABLIER_FLOW.void(streamId);
    }

    /// @dev Refunds the entire refundable amount of tokens from the compensation component stream to the sender's address
    /// See the documentation in {ISablierFlow-refundMax}
    function _refundComponentStream(uint256 streamId) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Refund the stream
        $.SABLIER_FLOW.refundMax(streamId);
    }

    /// @dev See the documentation in {ISablierFlow-getStream}
    function _getStream(uint256 streamId) internal view returns (Flow.Stream memory stream) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Return the stream
        return $.SABLIER_FLOW.getStream(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OTHER INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Allows only the initial stream sender to execute management-related actions
    ///
    /// Notes:
    /// - A private function is used instead of a modifier to avoid two redundant SLOAD operations,
    /// in a scenario where the storage layout is accessed in both the modifier and the function that
    /// uses the modifier. As a result, the overall gas cost is reduced because an SLOAD followed by a
    /// JUMP is cheaper than performing two separate SLOADs.
    function _onlyInitialStreamSender(uint256 streamId) private view returns (FlowStreamManagerStorage storage $) {
        // Retrieve the storage of the {FlowStreamManager} contract
        $ = _getFlowStreamManagerStorage();

        // Checks: the `msg.sender` is the initial stream creator
        address initialSender = $.initialStreamSender[streamId];
        if (msg.sender != initialSender) revert Errors.OnlyInitialStreamSender(initialSender);
    }

    /// @dev Transfers the `amount` of `asset` tokens to this address (or the contract inherting from)
    /// and approves the `SablierFlow` contract to spend the amount
    function _transferFromAndApprove(IERC20 asset, uint128 amount, address spender) internal {
        // Transfer the provided amount of ERC-20 tokens to this contract
        asset.safeTransferFrom({ from: msg.sender, to: address(this), value: amount });

        // Approve the Sablier Flow contract to spend the ERC-20 tokens
        asset.approve(spender, amount);
    }
}
