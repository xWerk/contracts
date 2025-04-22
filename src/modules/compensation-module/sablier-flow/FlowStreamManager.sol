// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Broker } from "@sablier/flow/src/types/DataTypes.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { IFlowStreamManager } from "./interfaces/IFlowStreamManager.sol";
import { Types } from "../libraries/Types.sol";

/// @title FlowStreamManager
/// @notice See the documentation in {IFlowStreamManager}
contract FlowStreamManager is IFlowStreamManager, Initializable, OwnableUpgradeable {
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

    /// @dev  Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    function SABLIER_FLOW() public view override returns (ISablierFlow) {
        return _getFlowStreamManagerStorage().SABLIER_FLOW;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlowStreamManager
    function createFlowStream(address recipient, Types.Package memory package) external returns (uint256 streamId) {
        // Retrieve the storage of the {FlowStreamManager} contract
        FlowStreamManagerStorage storage $ = _getFlowStreamManagerStorage();

        // Create the flow stream using the `create` function
        streamId = $.SABLIER_FLOW.create({
            sender: msg.sender, // The sender will be able to pause the stream or change rate per second
            recipient: recipient, // The recipient of the streamed tokens
            ratePerSecond: package.ratePerSecond, // The rate per second of the stream
            token: package.asset, // The streaming token
            transferable: false // Whether the stream will be transferable or not
         });
    }
}
