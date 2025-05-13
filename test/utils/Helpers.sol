// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "src/modules/payment-module/libraries/Types.sol";
import { Helpers as PaymentHelpers } from "src/modules/payment-module/libraries/Helpers.sol";

library Helpers {
    /// @dev Calculates the number of payments that must be done based on a recurring payment request
    function computeNumberOfRecurringPayments(
        Types.Recurrence recurrence,
        uint40 interval
    )
        internal
        pure
        returns (uint40 numberOfPayments)
    {
        if (recurrence == Types.Recurrence.Weekly) {
            numberOfPayments = interval / 1 weeks;
        } else if (recurrence == Types.Recurrence.Monthly) {
            numberOfPayments = interval / 4 weeks;
        } else if (recurrence == Types.Recurrence.Yearly) {
            numberOfPayments = interval / 48 weeks;
        }
    }

    /// @dev Checks if the fuzzed recurrence and payment method are valid;
    /// Check {IPaymentModule-createRequest} for reference
    function checkFuzzedPaymentMethod(
        uint8 paymentMethod,
        uint8 recurrence,
        uint40 startTime,
        uint40 endTime
    )
        internal
        pure
        returns (bool valid, uint40 numberOfPayments)
    {
        if (paymentMethod == uint8(Types.Method.Transfer) && recurrence == uint8(Types.Recurrence.OneOff)) {
            numberOfPayments = 1;
        } else if (
            paymentMethod == uint8(Types.Method.TranchedStream)
                || (paymentMethod == uint8(Types.Method.Transfer) && recurrence != uint8(Types.Recurrence.OneOff))
        ) {
            // Break fuzz test if payment method is tranched stream and recurrence set to one-off
            // as a tranched stream recurrence must be Weekly, Monthly or Yearly
            if (recurrence == uint8(Types.Recurrence.OneOff)) {
                return (false, 0);
            }

            numberOfPayments = PaymentHelpers.computeNumberOfPayments({
                recurrence: Types.Recurrence(recurrence),
                interval: endTime - startTime
            });

            // Check if the interval is too short for the fuzzed recurrence
            // due to zero payments that must be done
            if (numberOfPayments == 0) return (false, 0);

            if (paymentMethod == uint8(Types.Method.TranchedStream)) {
                // Check for the maximum number of tranched steps in a Tranched Stream
                if (numberOfPayments > 500) return (false, 0);

                numberOfPayments = 1;
            }
        } else if (paymentMethod == uint8(Types.Method.LinearStream)) {
            numberOfPayments = 1;
        }

        return (true, numberOfPayments);
    }

    /// @dev Retrieves the duration of each tranche from a tranched stream based on a recurrence
    function _getDurationPerTrache(Types.Recurrence recurrence) internal pure returns (uint40 duration) {
        if (recurrence == Types.Recurrence.Weekly) duration = 1 weeks;
        else if (recurrence == Types.Recurrence.Monthly) duration = 4 weeks;
        else if (recurrence == Types.Recurrence.Yearly) duration = 48 weeks;
    }
}
