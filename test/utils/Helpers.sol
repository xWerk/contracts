// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../../src/modules/invoice-module/libraries/Types.sol";
import { Helpers as InvoiceHelpers } from "./../../src/modules/invoice-module/libraries/Helpers.sol";

library Helpers {
    function createInvoiceDataType() public view returns (Types.Invoice memory) {
        return
            Types.Invoice({
                status: Types.Status.Pending,
                startTime: 0,
                endTime: uint40(block.timestamp) + 1 weeks,
                payment: Types.Payment({
                    method: Types.Method.Transfer,
                    recurrence: Types.Recurrence.OneOff,
                    paymentsLeft: 1,
                    asset: address(0),
                    amount: uint128(1 ether),
                    streamId: 0
                })
            });
    }

    /// @dev Calculates the number of payments that must be done based on a Recurring invoice
    function computeNumberOfRecurringPayments(
        Types.Recurrence recurrence,
        uint40 interval
    ) internal pure returns (uint40 numberOfPayments) {
        if (recurrence == Types.Recurrence.Weekly) {
            numberOfPayments = interval / 1 weeks;
        } else if (recurrence == Types.Recurrence.Monthly) {
            numberOfPayments = interval / 4 weeks;
        } else if (recurrence == Types.Recurrence.Yearly) {
            numberOfPayments = interval / 48 weeks;
        }
    }

    /// @dev Checks if the fuzzed recurrence and payment method are valid;
    /// Check {IInvoiceModule-createInvoice} for reference
    function checkFuzzedPaymentMethod(
        uint8 paymentMethod,
        uint8 recurrence,
        uint40 startTime,
        uint40 endTime
    ) internal pure returns (bool valid, uint40 numberOfPayments) {
        if (paymentMethod == uint8(Types.Method.Transfer) && recurrence == uint8(Types.Recurrence.OneOff)) {
            numberOfPayments = 1;
        } else if (paymentMethod != uint8(Types.Method.LinearStream)) {
            numberOfPayments = InvoiceHelpers.computeNumberOfPayments({
                recurrence: Types.Recurrence(recurrence),
                interval: endTime - startTime
            });

            // Check if the interval is too short for the fuzzed recurrence
            // due to zero payments that must be done
            if (numberOfPayments == 0) return (false, 0);

            if (paymentMethod == uint8(Types.Method.TranchedStream)) {
                // Check for the maximum number of tranched steps in a Tranched Stream
                if (numberOfPayments > 500) return (false, 0);

                numberOfPayments = 0;
            }
        }

        // Break fuzz test if payment method is tranched stream and recurrence set to one-off
        // as a tranched stream recurrence must be Weekly, Monthly or Yearly
        if (paymentMethod == uint8(Types.Method.TranchedStream)) {
            if (recurrence == uint8(Types.Recurrence.OneOff)) {
                return (false, 0);
            }
        }

        return (true, numberOfPayments);
    }
}
