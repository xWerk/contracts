// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "../libraries/Types.sol";

/// @title ICompensationModule
/// @notice Module that provides functionalities to create onchain compensation packages
interface ICompensationModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a compensation plan is created
    /// @param compensationId The ID of the compensation plan
    /// @param recipient The address of the recipient of the compensation packages
    event CompensationCreated(uint256 indexed compensationId, address indexed recipient);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new compensation plan for the `recipient` recipient
    /// @param recipient The address of the recipient of the compensation
    /// @param packages The packages included in the compensation (salary, ESOPs, bonuses, etc.)
    /// @return compensationId The ID of the newly created compensation
    function createCompensation(
        address recipient,
        Types.Package[] memory packages
    )
        external
        returns (uint256 compensationId);
}
