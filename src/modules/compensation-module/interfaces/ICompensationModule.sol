// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "../libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ICompensationModule
/// @notice Module that provides functionalities to create onchain compensation components
interface ICompensationModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a compensation component is created
    /// @param componentId The ID of the compensation component
    /// @param recipient The address of the recipient of the compensation component
    /// @param streamId The ID of the compensation component stream
    event ComponentCreated(uint256 indexed componentId, address indexed recipient, uint256 indexed streamId);

    /// @notice Emitted when a compensation component rate per second is adjusted
    /// @param componentId The ID of the compensation component
    /// @param newRatePerSecond The new rate per second of the compensation component
    event ComponentRatePerSecondAdjusted(uint256 indexed componentId, UD21x18 newRatePerSecond);

    /// @notice Emitted when a component stream is deposited
    /// @param componentId The ID of the compensation component
    /// @param amount The amount deposited to the component stream
    event ComponentDeposited(uint256 indexed componentId, uint128 amount);

    /// @notice Emitted when a component stream is withdrawn
    /// @param componentId The ID of the compensation component
    /// @param amount The amount withdrawn from the component stream
    event ComponentWithdrawn(uint256 indexed componentId, uint128 amount);

    /// @notice Emitted when a component stream is paused
    /// @param componentId The ID of the compensation component
    event ComponentPaused(uint256 indexed componentId);

    /// @notice Emitted when a component stream is restarted
    /// @param componentId The ID of the compensation component
    /// @param newRatePerSecond The new rate per second of the compensation component
    event ComponentRestarted(uint256 indexed componentId, UD21x18 newRatePerSecond);

    /// @notice Emitted when a component stream is cancelled
    /// @param componentId The ID of the compensation component
    event ComponentCancelled(uint256 indexed componentId);

    /// @notice Emitted when a component stream is refunded
    /// @param componentId The ID of the compensation component
    event ComponentRefunded(uint256 indexed componentId);

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the compensation component details with the given ID
    /// @param componentId The ID of the compensation component
    function getComponent(uint256 componentId) external view returns (Types.CompensationComponent memory);

    /// @notice Returns the component stream details with the given ID
    /// @param streamId The ID of the component stream
    function getComponentStream(uint256 streamId) external view returns (Flow.Stream memory stream);

    /// @notice Returns the status of a component stream
    /// @param componentId The ID of the compensation component
    function statusOfComponent(uint256 componentId) external view returns (Flow.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new compensation for the `recipient` recipient
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account
    ///
    /// @param recipient The address of the recipient of the compensation
    /// @param ratePerSecond The rate per second of the compensation component
    /// @param componentType The type of compensation component
    /// @param asset The address of the compensation asset
    ///
    /// @return componentId The ID of the newly created compensation
    /// @return streamId The ID of the newly created component stream
    function createComponent(
        address recipient,
        UD21x18 ratePerSecond,
        Types.ComponentType componentType,
        IERC20 asset
    )
        external
        returns (uint256 componentId, uint256 streamId);

    /// @notice Adjusts the rate per second of a compensation component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    /// - `newRatePerSecond` must not equal to the current rate per second or be zero
    ///
    /// @param componentId The ID of the compensation component
    /// @param newRatePerSecond The new rate per second of the compensation component
    function adjustComponentRatePerSecond(uint256 componentId, UD21x18 newRatePerSecond) external;

    /// @notice Deposits an amount to a compensation component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    /// - `amount` must be greater than zero
    ///
    /// @param componentId The ID of the compensation component
    /// @param amount The amount to deposit
    function depositToComponent(uint256 componentId, uint128 amount) external;

    /// @notice Withdraws the maximum amount from a compensation component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component recipient
    /// - `componentId` must not reference a null component
    ///
    /// @param componentId The ID of the compensation component
    function withdrawFromComponent(uint256 componentId) external returns (uint128 withdrawnAmount);

    /// @notice Pauses a compensation component by setting its rate per second to zero
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    ///
    /// @param componentId The ID of the compensation component
    function pauseComponent(uint256 componentId) external;

    /// @notice Cancels a compensation component by forfeiting its uncovered debt (if any) and marking it as voided
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    ///
    /// @param componentId The ID of the compensation component
    function cancelComponent(uint256 componentId) external;

    /// @notice Refunds the entire refundable amount of tokens from a component stream to the sender's address
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    ///
    /// @param componentId The ID of the compensation component
    function refundComponent(uint256 componentId) external;

    /// @notice Restarts a compensation component by resuming its stream with a new rate per second
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the component sender
    /// - `componentId` must not reference a null component
    ///
    /// @param componentId The ID of the compensation component
    function restartComponent(uint256 componentId, UD21x18 newRatePerSecond) external;
}
