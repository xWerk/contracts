// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "../libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

/// @title ICompensationModule
/// @notice Module that provides functionalities to create onchain compensation plans
interface ICompensationModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a compensation plan is created
    /// @param compensationPlanId The ID of the compensation plan
    /// @param recipient The address of the recipient of the compensation plan
    event CompensationPlanCreated(uint256 indexed compensationPlanId, address indexed recipient);

    /// @notice Emitted when a compensation plan component rate per second is adjusted
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param newRatePerSecond The new rate per second of the compensation plan component
    event ComponentRatePerSecondAdjusted(
        uint256 indexed compensationPlanId, uint96 indexed componentId, UD21x18 newRatePerSecond
    );

    /// @notice Emitted when a compensation plan component stream is deposited
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param amount The amount deposited to the compensation plan component stream
    event CompensationComponentDeposited(
        uint256 indexed compensationPlanId, uint96 indexed componentId, uint128 amount
    );

    /// @notice Emitted when a compensation plan component stream is withdrawn
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param withdrawnAmount The amount withdrawn from the compensation plan component stream
    event CompensationComponentWithdrawn(
        uint256 indexed compensationPlanId, uint96 indexed componentId, uint128 withdrawnAmount
    );

    /// @notice Emitted when a compensation plan component stream is paused
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    event CompensationComponentPaused(uint256 indexed compensationPlanId, uint96 indexed componentId);

    /// @notice Emitted when a compensation plan component stream is cancelled
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    event CompensationComponentCancelled(uint256 indexed compensationPlanId, uint96 indexed componentId);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new compensation plan for the `recipient` recipient
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account
    ///
    /// @param recipient The address of the recipient of the compensation
    /// @param components The components included in the compensation plan (salary, ESOPs, bonuses, etc.)
    /// @return compensationPlanId The ID of the newly created compensation
    function createCompensationPlan(
        address recipient,
        Types.Component[] memory components
    )
        external
        returns (uint256 compensationPlanId);

    /// @notice Creates new compensation plans in batch for the `recipients` recipients
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account
    ///
    /// @param recipients The addresses of the recipients of the compensation plans
    /// @param components The components included in the compensation plans (salary, ESOPs, bonuses, etc.) of each recipient
    function createBatchCompensationPlan(address[] memory recipients, Types.Component[][] memory components) external;

    /// @notice Adjusts the rate per second of a compensation plan component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account
    /// - `msg.sender` must be the compensation plan sender
    /// - `componentId` must not reference a null compensation plan component
    /// - `newRatePerSecond` must not equal to the current rate per second or be zero
    ///
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param newRatePerSecond The new rate per second of the compensation plan component
    function adjustComponentRatePerSecond(
        uint256 compensationPlanId,
        uint96 componentId,
        UD21x18 newRatePerSecond
    )
        external;

    /// @notice Deposits an amount to a compensation plan component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the compensation plan sender
    /// - `componentId` must not reference a null compensation plan component
    /// - `amount` must be greater than zero
    ///
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param amount The amount to deposit
    function depositToComponent(uint256 compensationPlanId, uint96 componentId, uint128 amount) external;

    /// @notice Withdraws the maximum amount from a compensation plan component
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the compensation plan recipient
    /// - `componentId` must not reference a null compensation plan component
    ///
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    function withdrawFromComponent(
        uint256 compensationPlanId,
        uint96 componentId
    )
        external
        returns (uint128 withdrawnAmount);

    /// @notice Pauses a compensation plan component stream
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the compensation plan sender
    /// - `compensationPlanId` must not reference a null compensation plan
    /// - `componentId` must not reference a null compensation plan component
    ///
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    function pauseComponentStream(uint256 compensationPlanId, uint96 componentId) external;

    /// @notice Cancels a compensation plan component stream
    ///
    /// Notes:
    /// - `msg.sender` must be a valid Space account and the compensation plan sender
    /// - `compensationPlanId` must not reference a null compensation plan
    /// - `componentId` must not reference a null compensation plan component
    ///
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    function cancelComponentStream(uint256 compensationPlanId, uint96 componentId) external;
}
