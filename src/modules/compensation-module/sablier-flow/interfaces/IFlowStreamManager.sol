// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

/// @title IFlowStreamManager
/// @notice Contract used to create and manage Sablier Flow compatible streams through a set of internal functions
/// @dev This code is referenced in the Sablier Flow docs: https://docs.sablier.com/guides/flow/overview
interface IFlowStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the address of the {SablierFlow} contract is updated
    /// @param oldAddress The old address of the {SablierFlow} contract
    /// @param newAddress The new address of the {SablierFlow} contract
    event SablierFlowAddressUpdated(ISablierFlow oldAddress, ISablierFlow newAddress);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address of the {SablierFlow} contract used to create compensation streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/guides/flow/deployments
    function SABLIER_FLOW() external view returns (ISablierFlow);

    /// @notice Returns the status of a compensation component stream
    /// @dev See the documentation in {ISablierFlow-statusOf}
    /// @param streamId The ID of the compensation component stream
    /// @return status The status of the compensation component stream
    function statusOf(uint256 streamId) external view returns (Flow.Status status);

    /// @notice Returns the withdrawable amount of a stream
    /// @dev See the documentation in {ISablierFlow-withdrawableAmountOf}
    /// @param streamId The ID of the compensation component stream
    /// @return withdrawableAmount The amount withdrawable by the recipient
    function withdrawableAmountOf(uint256 streamId) external view returns (uint128 withdrawableAmount);

    /// @notice Returns the refundable amount of a stream
    /// @dev See the documentation in {ISablierFlow-refundableAmountOf}
    /// @param streamId The ID of the compensation component stream
    /// @return refundableAmount The amount that the sender can be refunded from the stream
    function refundableAmountOf(uint256 streamId) external view returns (uint128 refundableAmount);

    /// @notice Returns the minimum fee required to withdraw from the stream
    /// @dev See the documentation in {ISablierFlow-calculateMinFeeWei}
    /// @param streamId The ID of the component stream
    /// @return minFee the minimum fee required to withdraw from the stream
    function calculateMinFeeWei(uint256 streamId) external view returns (uint256 minFee);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the address of the {SablierFlow} contract used to create and manage compensation streams
    ///
    /// Notes:
    /// - `msg.sender` must be the owner
    ///
    /// @param newSablierFlow The new address of the {SablierFlow} contract
    function updateSablierFlow(ISablierFlow newSablierFlow) external;
}
