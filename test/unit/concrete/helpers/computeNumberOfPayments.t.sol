// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../../../Base.t.sol";
import { Helpers } from "./../../../../src/modules/invoice-module/libraries/Helpers.sol";
import { Types } from "./../../../../src/modules/invoice-module/libraries/Types.sol";

contract ComputeNumberOfPayments_Helpers_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function test_ComputeNumberOfPayments_Weekly() external view {
        // Create an interval of 11 weeks
        uint40 startTime = uint40(block.timestamp);
        uint40 endTime = uint40(block.timestamp + 11 weeks);

        // Run the test
        uint40 numberOfPayments = Helpers.computeNumberOfPayments({
            recurrence: Types.Recurrence.Weekly,
            interval: endTime - startTime
        });

        // Assert the actual and expected number of payments
        assertEq(numberOfPayments, 11);
    }

    function test_ComputeNumberOfPayments_Monthly() external view {
        // Create an interval of 2 months
        uint40 startTime = uint40(block.timestamp);
        uint40 endTime = uint40(block.timestamp + 2 * 4 weeks);

        // Run the test
        uint40 numberOfPayments = Helpers.computeNumberOfPayments({
            recurrence: Types.Recurrence.Monthly,
            interval: endTime - startTime
        });

        // Assert the actual and expected number of payments
        assertEq(numberOfPayments, 2);
    }

    function test_ComputeNumberOfPayments_Yearly() external view {
        // Create an interval of 3 years
        uint40 startTime = uint40(block.timestamp);
        uint40 endTime = uint40(block.timestamp + 3 * 48 weeks);

        // Run the test
        uint40 numberOfPayments = Helpers.computeNumberOfPayments({
            recurrence: Types.Recurrence.Yearly,
            interval: endTime - startTime
        });

        // Assert the actual and expected number of payments
        assertEq(numberOfPayments, 3);
    }
}
