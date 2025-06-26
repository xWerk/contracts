// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.22;

import { Broker, Lockup } from "@sablier/lockup/src/types/DataTypes.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Types } from "src/modules/payment-module/libraries/Types.sol";

/// @title IStreamManager
/// @notice Contract used to create and manage Sablier Lockup compatible streams
/// @dev This code is referenced in the docs: https://docs.sablier.com/concepts/protocol/stream-types
interface IStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the broker fee is updated
    /// @param oldFee The old broker fee
    /// @param newFee The new broker fee
    event BrokerFeeUpdated(UD60x18 oldFee, UD60x18 newFee);

    /// @notice Emitted when the address of the {SablierLockup} contract is updated
    /// @param oldAddress The old address of the {SablierLockup} contract
    /// @param newAddress The new address of the {SablierLockup} contract
    event SablierLockupAddressUpdated(ISablierLockup oldAddress, ISablierLockup newAddress);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address of the {SablierLockup} contract used to create linear and tranched streams
    /// @dev This is initialized after deploymentand it might be different depending on the deployment chain
    /// See https://docs.sablier.com/guides/lockup/deployments
    function SABLIER_LOCKUP() external view returns (ISablierLockup sablierLockup);

    /// @notice The broker account andfee charged to create Sablier Lockup stream
    function broker() external view returns (Broker memory brokerConfig);

    /// @notice See the documentation in {ISablierLockup-getDepositedAmount}
    function getDepositedAmount(uint256 streamId) external view returns (uint128 depositedAmount);

    /// @notice See the documentation in {ISablierLockup-getRecipient}
    function getRecipient(uint256 streamId) external view returns (address recipient);

    /// @notice See the documentation in {ISablierLockup-getSender}
    function getSender(uint256 streamId) external view returns (address sender);

    /// @notice See the documentation in {ISablierLockup-getRefundedAmount}
    function getRefundedAmount(uint256 streamId) external view returns (uint128 refundedAmount);

    /// @notice See the documentation in {ISablierLockup-getStartTime}
    function getStartTime(uint256 streamId) external view returns (uint40 startTime);

    /// @notice See the documentation in {ISablierLockup-getEndTime}
    function getEndTime(uint256 streamId) external view returns (uint40 endTime);

    /// @notice See the documentation in {ISablierLockup-getUnderlyingToken}
    function getUnderlyingToken(uint256 streamId) external view returns (IERC20 underlyingToken);

    /// @notice See the documentation in {ISablierLockup-withdrawableAmountOf}
    function withdrawableAmountOf(uint256 streamId) external view returns (uint128 withdrawableAmount);

    /// @notice See the documentation in {ISablierLockup-streamedAmountOf}
    function streamedAmountOf(uint256 streamId) external view returns (uint128 streamedAmount);

    /// @notice See the documentation in {ISablierLockup-statusOf}
    function statusOfStream(uint256 streamId) external view returns (Lockup.Status status);

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

    /// @notice Updates the address of the {SablierLockup} contract used to create linear and tranched streams
    ///
    /// Notes:
    /// - `msg.sender` must be the owner
    ///
    /// @param newSablierLockup The new address of the {SablierLockup} contract
    function updateSablierLockup(ISablierLockup newSablierLockup) external;
}
