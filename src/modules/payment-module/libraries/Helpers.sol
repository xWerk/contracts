// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./Types.sol";

/// @title Helpers
/// @notice Library with helpers used across the {InvoiceModule} contract
library Helpers {
    /// @dev Calculates the number of payments that must be done for a recurring transfer or tranched stream invoice
    /// Notes:
    /// - Known issue: due to leap seconds, not every year equals 365 days and not every day has 24 hours
    /// - See https://docs.soliditylang.org/en/v0.8.26/units-and-global-variables.html#time-units
    function computeNumberOfPayments(
        Types.Recurrence recurrence,
        uint40 interval
    ) internal pure returns (uint40 numberOfPayments) {
        // Calculate the number of payments based on the recurrence type
        if (recurrence == Types.Recurrence.Weekly) {
            numberOfPayments = interval / 1 weeks;
        } else if (recurrence == Types.Recurrence.Monthly) {
            numberOfPayments = interval / 4 weeks;
        } else if (recurrence == Types.Recurrence.Yearly) {
            numberOfPayments = interval / 48 weeks;
        }
    }
}
