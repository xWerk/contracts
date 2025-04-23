// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Namespace for the structs used across the {CompensationModule} related contracts
library Types {
    /// @notice Struct encapsulating the different values describing a compensation plan
    /// @param recipient The address of compensation recipient
    /// @param nextPackageId The next package ID to be used
    /// @param packages The packages included in the compensation (salary, ESOPs, bonuses, etc.) by their IDs
    struct Compensation {
        address recipient;
        uint96 nextPackageId;
        mapping(uint256 packageId => Package package) packages;
    }

    /// @notice Struct encapsulating the different values describing a package within a compensation plan
    /// @param packageType The type of compensation package
    /// @param asset The address of the compensation asset
    /// @param ratePerSecond The rate per second of the compensation package
    /// @param amount The amount of compensation
    /// @param streamId The ID of the stream used to pay the compensation package
    struct Package {
        // slot 0
        PackageType packageType; // 1 byte
        IERC20 asset; // 20 bytes
        // slot 1
        UD21x18 ratePerSecond; // 16 bytes
        uint128 amount; // 16 bytes
        // slot 2
        uint256 streamId; // 32 bytes
    }

    /// @notice Enum representing the different types of a compensation package
    /// @custom:value Payroll Compensation package for a payroll
    /// @custom:value Payout Compensation package for a payout
    /// @custom:value ESOP Compensation package for a ESOP
    enum PackageType {
        Payroll,
        Payout,
        ESOP
    }
}
