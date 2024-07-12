// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.22;

import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { Types } from "./../../libraries/Types.sol";

/// @title IStreamCreator
/// @notice Contract used to create Sablier V2 compatible streams
/// @dev This code is referenced in the docs: https://docs.sablier.com/concepts/protocol/stream-types
interface IStreamCreator {
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

    /// @notice The address of the broker admin account or contract managing the broker fee
    function brokerAdmin() external view returns (address);

    /// @notice The broker fee charged to create Sablier V2 stream
    /// @dev See the `UD60x18` type definition in the `@prb/math/src/ud60x18/ValueType.sol file`
    function brokerFee() external view returns (UD60x18);

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
    ) external returns (uint256 streamId);

    /// @notice Creates a Lockup Tranched stream; See https://docs.sablier.com/concepts/protocol/stream-types#lockup-tranched
    /// @param asset The address of the ERC-20 token to be streamed
    /// @param totalAmount The total amount of ERC-20 tokens to be streamed
    /// @param startTime The timestamp when the stream takes effect
    /// @param endTime The timestamp by which the stream must be paid
    /// @param recipient The address receiving the ERC-20 tokens
    /// @param recurrence The recurrence of each tranche
    function createTranchedStream(
        IERC20 asset,
        uint128 totalAmount,
        uint40 startTime,
        uint40 endTime,
        address recipient,
        Types.Recurrence recurrence
    ) external returns (uint256 streamId);

    /// @notice Updates the fee charged by the broker
    ///
    /// Notes:
    /// - The new fee will be applied only to the new streams hence it can't be retrospectively updated
    ///
    /// @param newBrokerFee The new broker fee
    function updateBrokerFee(UD60x18 newBrokerFee) external;
}