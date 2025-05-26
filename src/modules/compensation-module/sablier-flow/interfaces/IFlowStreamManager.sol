// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Broker, Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { Types } from "../../libraries/Types.sol";

/// @title IFlowStreamManager
/// @notice Contract used to create and manage Sablier Flow compatible streams through a set of internal functions
/// @dev This code is referenced in the Sablier Flow docs: https://docs.sablier.com/guides/flow/overview
interface IFlowStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the broker fee is updated
    /// @param oldFee The old broker fee
    /// @param newFee The new broker fee
    event BrokerFeeUpdated(UD60x18 oldFee, UD60x18 newFee);

    /// @notice Emitted when the address of the {SablierFlow} contract is updated
    /// @param oldAddress The old address of the {SablierFlow} contract
    /// @param newAddress The new address of the {SablierFlow} contract
    event SablierFlowAddressUpdated(ISablierFlow oldAddress, ISablierFlow newAddress);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The broker account and fee charged to deposit on Sablier Flow streams
    function broker() external view returns (Broker memory brokerConfig);

    /// @notice The address of the {SablierFlow} contract used to create compensation streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/guides/flow/deployments
    function SABLIER_FLOW() external view returns (ISablierFlow);

    /// @notice Returns the status of a compensation component stream
    /// @dev See the documentation in {ISablierFlow-statusOf}
    /// @param streamId The ID of the compensation component stream
    /// @return status The status of the compensation component stream
    function statusOfComponentStream(uint256 streamId) external view returns (Flow.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the fee charged by the broker
    ///
    /// Notes:
    /// - `msg.sender` must be the owner
    /// - The new fee will be applied only to the new streams hence it can't be retrospectively updated
    ///
    /// @param newBrokerFee The new broker fee
    function updateStreamBrokerFee(UD60x18 newBrokerFee) external;

    /// @notice Updates the address of the {SablierFlow} contract used to create and manage compensation streams
    ///
    /// Notes:
    /// - `msg.sender` must be the owner
    ///
    /// @param newSablierFlow The new address of the {SablierFlow} contract
    function updateSablierFlow(ISablierFlow newSablierFlow) external;
}
