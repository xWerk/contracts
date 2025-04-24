// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Types } from "../../libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

/// @title IFlowStreamManager
/// @notice Contract used to create and manage Sablier Flow compatible streams
/// @dev This code is referenced in the Sablier Flow docs: https://docs.sablier.com/guides/flow/overview
interface IFlowStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address of the {SablierFlow} contract used to create compensation streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/guides/flow/deployments
    function SABLIER_FLOW() external view returns (ISablierFlow);

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the status of a compensation component stream
    /// @dev See the documentation in {ISablierFlow-statusOf}
    /// @param streamId The ID of the compensation component stream
    /// @return status The status of the compensation component stream
    function statusOfComponentStream(uint256 streamId) external view returns (Flow.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Sablier flow stream without upfront deposit for a compensation component
    /// @dev See the documentation in {ISablierFlow-create}
    /// @param recipient The address of the recipient of the compensation component
    /// @param component The component of the compensation plan to be streamed
    /// @return streamId The ID of the newly created stream
    function createComponentStream(
        address recipient,
        Types.Component memory component
    )
        external
        returns (uint256 streamId);

    /// @notice See the documentation in {ISablierFlow-adjustRatePerSecond}
    function adjustComponentStreamRatePerSecond(uint256 streamId, UD21x18 newRatePerSecond) external;

    /// @notice See the documentation in {ISablierFlow-deposit}
    function depositToComponentStream(uint256 streamId, uint128 amount, address sender, address recipient) external;

    /// @notice See the documentation in {ISablierFlow-withdrawMax}
    function withdrawMaxFromComponentStream(uint256 streamId, address to) external returns (uint128);

    /// @notice See the documentation in {ISablierFlow-pause}
    function pauseComponentStream(uint256 streamId) external;

    /// @notice Cancels a compensation component stream by forfeiting its uncovered debt (if any) and marking it as voided
    /// @dev See the documentation in {ISablierFlow-void}
    function cancelComponentStream(uint256 streamId) external;

    /// @notice Refunds the entire refundable amount of tokens from the compensation component stream to the sender's address
    /// @dev See the documentation in {ISablierFlow-refundMax}
    function refundComponentStream(uint256 streamId) external;
}
