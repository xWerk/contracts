// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IFlowStreamManager } from "./interfaces/IFlowStreamManager.sol";
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
        address _initialAdmin
    )
        internal
        onlyInitializing
    {
        __Ownable_init(_initialAdmin);

        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Set the Sablier Flow contract address
        $.SABLIER_FLOW = _sablierFlow;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlowStreamManager
    function SABLIER_FLOW() public view override returns (ISablierFlow) {
        return _getFlowStreamManagerStorage().SABLIER_FLOW;
    }

    /// @inheritdoc IFlowStreamManager
    function statusOf(uint256 streamId) public view returns (Flow.Status status) {
        // Return the status of the stream
        return SABLIER_FLOW().statusOf(streamId);
    }

    /// @inheritdoc IFlowStreamManager
    function withdrawableAmountOf(uint256 streamId) public view returns (uint128 withdrawableAmount) {
        // Return the withdrawable amount from the stream
        return SABLIER_FLOW().withdrawableAmountOf(streamId);
    }

    /// @inheritdoc IFlowStreamManager
    function calculateMinFeeWei(uint256 streamId) public view returns (uint256 minFee) {
        // Return the minimum fee required to withdraw from the stream
        return SABLIER_FLOW().calculateMinFeeWei(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlowStreamManager
    function updateSablierFlow(ISablierFlow newSablierFlow) public onlyOwner {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        emit SablierFlowAddressUpdated({ oldAddress: $.SABLIER_FLOW, newAddress: newSablierFlow });

        // Update the address of the {SablierFlow} contract
        $.SABLIER_FLOW = newSablierFlow;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SABLIER FLOW-SPECIFIC INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates a new Sablier Flow stream without upfront deposit for a compensation component
    /// @dev See the documentation in {ISablierFlow-create}
    /// @param recipient The address of the recipient of the compensation component
    /// @param ratePerSecond The rate per second of the compensation component
    /// @param asset The address of the compensation asset
    /// @return streamId The ID of the newly created stream
    function _createStream(
        address recipient,
        UD21x18 ratePerSecond,
        IERC20 asset
    )
        internal
        returns (uint256 streamId)
    {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Create the flow stream using the `create` function
        streamId = $.SABLIER_FLOW
            .create({
                sender: address(this), // The sender will be able to pause the stream or change rate per second
                recipient: recipient, // The recipient of the streamed tokens
                ratePerSecond: ratePerSecond, // The rate per second of the stream
                startTime: 0, // The starting time of the stream. Zero means startTime is block.timestamp
                token: asset, // The streaming token
                transferable: false // Whether the stream will be transferable or not
            });

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        $.initialStreamSender[streamId] = msg.sender;
    }

    /// @dev Creates a new Sablier Flow stream with an upfront deposit for a compensation component
    /// @dev See the documentation in {ISablierFlow-createAndDeposit}
    /// @param recipient The address of the recipient of the compensation component
    /// @param ratePerSecond The rate per second of the compensation component
    /// @param asset The address of the compensation asset
    /// @param amount The deposit amount, denoted in token's decimals
    /// @return streamId The ID of the newly created stream
    function _createAndDepositToStream(
        address recipient,
        UD21x18 ratePerSecond,
        IERC20 asset,
        uint128 amount
    )
        internal
        returns (uint256 streamId)
    {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Create the flow stream using the `create` function
        streamId = $.SABLIER_FLOW
            .createAndDeposit({
                sender: address(this), // The sender will be able to pause the stream or change rate per second
                recipient: recipient, // The recipient of the streamed tokens
                startTime: 0, // The starting time of the stream. Zero means startTime is block.timestamp
                ratePerSecond: ratePerSecond, // The rate per second of the stream
                token: asset, // The streaming token
                transferable: false, // Whether the stream will be transferable or not
                amount: amount // The deposit amount, denoted in token's decimals
            });

        // Set `msg.sender` as the initial stream sender to allow authenticated stream management
        $.initialStreamSender[streamId] = msg.sender;
    }

    /// @dev See the documentation in {ISablierFlow-adjustRatePerSecond}
    function _adjustStreamRatePerSecond(uint256 streamId, UD21x18 newRatePerSecond) internal {
        FlowStreamManagerStorage storage $ = _onlyInitialStreamSender(streamId);

        // Adjust the rate per second of the stream
        $.SABLIER_FLOW.adjustRatePerSecond(streamId, newRatePerSecond);
    }

    /// @dev See the documentation in {ISablierFlow-deposit}
    ///
    /// Notes:
    /// - The `sender` is automatically set to the address of the {FlowStreamManager} contract and the access
    /// control is handled by the private `_onlyInitialStreamSender` function
    function _depositToStream(uint256 streamId, IERC20 asset, uint128 amount, address recipient) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Transfer the provided amount of ERC-20 tokens to this contract and approve the Sablier Flow contract to spend it
        _transferFromAndApprove({ asset: asset, amount: amount, spender: address($.SABLIER_FLOW) });

        // Deposit the amount to the stream
        $.SABLIER_FLOW.deposit({ streamId: streamId, amount: amount, sender: address(this), recipient: recipient });
    }

    /// @dev See the documentation in {ISablierFlow-withdraw}
    function _withdrawFromStream(uint256 streamId, address to, uint128 amount) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Withdraw {amount} from the stream
        $.SABLIER_FLOW.withdraw{ value: msg.value }(streamId, to, amount);
    }

    /// @dev See the documentation in {ISablierFlow-withdrawMax}
    function _withdrawMaxFromStream(uint256 streamId, address to) internal returns (uint128 withdrawnAmount) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Withdraw the maximum amount from the stream
        withdrawnAmount = $.SABLIER_FLOW.withdrawMax{ value: msg.value }(streamId, to);
    }

    /// @dev See the documentation in {ISablierFlow-pause}
    function _pauseStream(uint256 streamId) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Checks: the `msg.sender` is the initial stream creator
        address initialSender = $.initialStreamSender[streamId];
        if (msg.sender != initialSender) revert Errors.OnlyInitialStreamSender(initialSender);

        // Pause the stream
        $.SABLIER_FLOW.pause(streamId);
    }

    /// @dev See the documentation in {ISablierFlow-restart}
    function _restartStream(uint256 streamId, UD21x18 newRatePerSecond) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Restart the stream
        $.SABLIER_FLOW.restart(streamId, newRatePerSecond);
    }

    /// @dev Cancels a compensation component stream by forfeiting its uncovered debt (if any) and marking it as voided
    /// See the documentation in {ISablierFlow-void}
    function _cancelStream(uint256 streamId) internal {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Cancel the stream
        $.SABLIER_FLOW.void(streamId);
    }

    /// @dev Refunds the entire refundable amount of tokens from the compensation component stream to the sender's address
    /// See the documentation in {ISablierFlow-refundMax}
    function _refundStream(
        uint256 streamId,
        IERC20 asset,
        address initialStreamSender
    )
        internal
        returns (uint128 refundedAmount)
    {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Refund the stream
        refundedAmount = $.SABLIER_FLOW.refundMax(streamId);

        // Transfer assets to {initialStreamSender}
        asset.safeTransfer({ to: initialStreamSender, value: refundedAmount });
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
    /// JUMP is cheaper than performing two separate SLOADs
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
