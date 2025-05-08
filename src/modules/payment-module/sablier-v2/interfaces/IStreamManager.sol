// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.22;

import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";
import { Broker, Lockup, LockupLinear, LockupTranched } from "@sablier/v2-core/src/types/DataTypes.sol";
import { ISablierV2Lockup } from "@sablier/v2-core/src/interfaces/ISablierV2Lockup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { Types } from "./../../libraries/Types.sol";

/// @title IStreamManager
/// @notice Contract used to create and manage Sablier V2 compatible streams
/// @dev This code is referenced in the docs: https://docs.sablier.com/concepts/protocol/stream-types
interface IStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the broker fee is updated
    /// @param oldFee The old broker fee
    /// @param newFee The new broker fee
    event BrokerFeeUpdated(UD60x18 oldFee, UD60x18 newFee);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address of the {SablierV2LockupLinear} contract used to create linear streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/contracts/v2/deployments
    function SABLIER_LOCKUP_LINEAR() external view returns (ISablierV2LockupLinear);

    /// @notice The address of the {SablierV2LockupTranched} contract used to create tranched streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/contracts/v2/deployments
    function SABLIER_LOCKUP_TRANCHED() external view returns (ISablierV2LockupTranched);

    /// @notice The broker account andfee charged to create Sablier V2 stream
    function broker() external view returns (Broker memory brokerConfig);

    /// @notice Retrieves a linear stream details according to the {LockupLinear.StreamLL} struct
    /// @param streamId The ID of the stream to be retrieved
    function getLinearStream(uint256 streamId) external view returns (LockupLinear.StreamLL memory stream);

    /// @notice Retrieves a tranched stream details according to the {LockupTranched.StreamLT} struct
    /// @param streamId The ID of the stream to be retrieved
    function getTranchedStream(uint256 streamId) external view returns (LockupTranched.StreamLT memory stream);

    /// @notice See the documentation in {ISablierV2Lockup-withdrawableAmountOf}
    /// Notes:
    /// - `streamType` parameter has been added to get the correct {ISablierV2Lockup} implementation
    function withdrawableAmountOf(
        Types.Method streamType,
        uint256 streamId
    )
        external
        view
        returns (uint128 withdrawableAmount);

    /// @notice See the documentation in {ISablierV2Lockup-streamedAmountOf}
    /// Notes:
    /// - `streamType` parameter has been added to get the correct {ISablierV2Lockup} implementation
    function streamedAmountOf(
        Types.Method streamType,
        uint256 streamId
    )
        external
        view
        returns (uint128 streamedAmount);

    /// @notice See the documentation in {ISablierV2Lockup-statusOf}
    /// Notes:
    /// - `streamType` parameter has been added to get the correct {ISablierV2Lockup} implementation
    function statusOfStream(Types.Method streamType, uint256 streamId) external view returns (Lockup.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the fee charged by the broker
    ///
    /// Notes:
    /// - `msg.sender` must be the broker admin
    /// - The new fee will be applied only to the new streams hence it can't be retrospectively updated
    ///
    /// @param newBrokerFee The new broker fee
    function updateStreamBrokerFee(UD60x18 newBrokerFee) external;
}
