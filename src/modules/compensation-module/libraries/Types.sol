// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Namespace for the structs used across the {CompensationModule} related contracts
library Types {
    /// @notice Struct encapsulating the different values describing a compensation plan
    /// @param recipient The address of compensation recipient
    /// @param nextComponentId The next compensationcomponent ID to be used
    /// @param components The components included in the compensation plan (salary, ESOPs, bonuses, etc.) by their IDs
    struct Compensation {
        address sender;
        address recipient;
        uint96 nextComponentId;
        mapping(uint256 componentId => Component component) components;
    }

    /// @notice Struct encapsulating the different values describing a component within a compensation plan
    /// @param componentType The type of compensation component
    /// @param asset The address of the compensation asset
    /// @param ratePerSecond The rate per second of the compensation component
    /// @param amount The amount of compensation
    /// @param streamId The ID of the stream used to pay the compensation component
    struct Component {
        // slot 0
        ComponentType componentType; // 1 byte
        IERC20 asset; // 20 bytes
        // slot 1
        UD21x18 ratePerSecond; // 16 bytes
        // slot 2
        uint256 streamId; // 32 bytes
    }

    /// @notice Enum representing the different types of a compensation component
    /// @custom:value Payroll Compensation component for a payroll
    /// @custom:value Payout Compensation component for a payout
    /// @custom:value ESOP Compensation component for a ESOP
    enum ComponentType {
        Payroll,
        Payout,
        ESOP
    }
}
