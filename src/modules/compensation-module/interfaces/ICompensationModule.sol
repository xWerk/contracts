// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "../libraries/Types.sol";

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

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new compensation plan for the `recipient` recipient
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
    /// @param recipients The addresses of the recipients of the compensation plans
    /// @param components The components included in the compensation plans (salary, ESOPs, bonuses, etc.) of each recipient
    function createBatchCompensationPlan(address[] memory recipients, Types.Component[][] memory components) external;
}
