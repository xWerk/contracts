// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Namespace for the structs used across the {CompensationModule} related contracts
library Types {
    /// @notice Struct encapsulating the different values describing a compensation component
    /// @param sender The address of compensation sender
    /// @param ratePerSecond The rate per second of the compensation component
    /// @param componentType The type of the compensation component
    /// @param recipient The address of compensation recipient
    /// @param asset The address of the compensation asset
    /// @param streamId The ID of the stream used to pay the compensation component
    struct CompensationComponent {
        address sender;
        UD21x18 ratePerSecond;
        ComponentType componentType;
        address recipient;
        IERC20 asset;
        uint256 streamId;
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
