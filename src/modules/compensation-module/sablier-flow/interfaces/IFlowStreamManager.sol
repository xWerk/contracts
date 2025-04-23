// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { Types } from "../../libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

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
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Sablier flow stream without upfront deposit
    /// @param recipient The address of the recipient of the compensation component
    /// @param component The component of the compensation plan to be streamed
    /// @return streamId The ID of the newly created stream
    function createFlowStream(
        address recipient,
        Types.Component memory component
    )
        external
        returns (uint256 streamId);

    /// @notice Adjusts the rate per second of a Sablier flow stream
    ///
    /// Notes:
    /// - `msg.sender` must be the stream sender
    /// - `streamId` must not reference a null or a paused stream
    /// - `newRatePerSecond` must not equal to the current rate per second
    ///
    /// @param streamId The ID of the stream to adjust
    /// @param newRatePerSecond The new rate per second of the stream
    function adjustFlowStreamRatePerSecond(uint256 streamId, UD21x18 newRatePerSecond) external;
}
