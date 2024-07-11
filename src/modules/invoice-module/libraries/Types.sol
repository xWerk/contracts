// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Namespace for the structs used across the Invoice Module contracts
library Types {
    enum Recurrence {
        OneOff,
        Weekly,
        Monthly,
        Yearly
    }

    enum Method {
        Transfer,
        LinearStream,
        TranchedStream
    }

    struct Payment {
        // slot 0
        Method method;
        Recurrence recurrence;
        uint24 paymentsLeft;
        address asset;
        // slot 1
        uint128 amount;
    }

    enum Status {
        Pending,
        Ongoing,
        Paid,
        Canceled
    }

    struct Invoice {
        // slot 0
        address recipient;
        Status status;
        uint40 startTime;
        uint40 endTime;
        // slot 1 and 2
        Payment payment;
    }
}
