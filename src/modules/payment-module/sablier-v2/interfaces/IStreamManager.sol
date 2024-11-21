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
    function LOCKUP_LINEAR() external view returns (ISablierV2LockupLinear);

    /// @notice The address of the {SablierV2LockupTranched} contract used to create tranched streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/contracts/v2/deployments
    function LOCKUP_TRANCHED() external view returns (ISablierV2LockupTranched);

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

    /// @notice Creates a Lockup Linear stream; See https://docs.sablier.com/concepts/protocol/stream-types#lockup-linear
    /// @param asset The address of the ERC-20 token to be streamed
    /// @param totalAmount The total amount of ERC-20 tokens to be streamed
    /// @param startTime The timestamp when the stream takes effect
    /// @param endTime The timestamp by which the stream must be paid
    /// @param recipient The address receiving the ERC-20 tokens
    function createLinearStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        uint40 endTime,
        address recipient
    )
        external
        returns (uint256 streamId);

    /// @notice Creates a Lockup Tranched stream; See https://docs.sablier.com/concepts/protocol/stream-types#lockup-tranched
    /// @param asset The address of the ERC-20 token to be streamed
    /// @param totalAmount The total amount of ERC-20 tokens to be streamed
    /// @param startTime The timestamp when the stream takes effect
    /// @param recipient The address receiving the ERC-20 tokens
    /// @param numberOfTranches The number of tranches paid by the stream
    /// @param recurrence The recurrence of each tranche
    function createTranchedStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        address recipient,
        uint128 numberOfTranches,
        Types.Recurrence recurrence
    )
        external
        returns (uint256 streamId);

    /// @notice Updates the fee charged by the broker
    ///
    /// Notes:
    /// - `msg.sender` must be the broker admin
    /// - The new fee will be applied only to the new streams hence it can't be retrospectively updated
    ///
    /// @param newBrokerFee The new broker fee
    function updateStreamBrokerFee(UD60x18 newBrokerFee) external;

    /// @notice See the documentation in {ISablierV2Lockup-withdrawMax}
    /// Notes:
    /// - `streamType` parameter has been added to get the correct {ISablierV2Lockup} implementation
    function withdrawMaxStream(
        Types.Method streamType,
        uint256 streamId,
        address to
    )
        external
        returns (uint128 withdrawnAmount);

    /// @notice See the documentation in {ISablierV2Lockup-cancel}
    /// Notes:
    /// - `streamType` parameter has been added to get the correct {ISablierV2Lockup} implementation
    function cancelStream(address sender, Types.Method streamType, uint256 streamId) external;
}
