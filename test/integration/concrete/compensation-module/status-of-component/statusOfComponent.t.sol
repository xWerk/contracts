// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

contract StatusOfComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.statusOfComponent({ componentId: 1 });
    }

    /// @dev Scenario for this test:
    /// - Payer creates a compensation component with one single component streaming USDT at a rate of `RATE_PER_SECOND` USDT/day
    /// - Payer does not deposit any USDT to the compensation component stream at this point
    function test_GivenComponentCreatedAndNotFunded() public whenComponentNotNull {
        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        // Once a stream is created without an initial deposit, it's balance will be 0
        // therefore the total debt will not exceed the stream balance
        assertEq(actualStatus, uint8(Flow.Status.STREAMING_SOLVENT));
    }

    /// @dev Scenario for this test:
    /// - Payer creates a compensation component with one single component streaming USDT at a rate of `RATE_PER_SECOND` USDT/day
    /// - Payer deposits 10 USDT to the compensation component starting the stream
    /// - After ~3 hours, the stream will become insolvent because all its balance will be fully streamed
    function test_GivenComponentCreatedAndPartiallyFunded() public whenComponentNotNull whenComponentPartiallyFunded {
        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        assertEq(actualStatus, uint8(Flow.Status.STREAMING_INSOLVENT));
    }

    /// @dev Scenario for this test:
    /// - Payer creates a compensation component with one single component streaming USDT at a rate of `RATE_PER_SECOND` USDT/day
    /// - Payer pauses the stream right after creation resulting in a paused stream with total debt not exceeding stream balance
    function test_GivenComponentNotFundedAndPaused() public whenComponentNotNull whenComponentPaused {
        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_SOLVENT));
    }

    /// @dev Scenario for this test relies on the same setup as the `test_GivenComponentPartiallyFundedAndPaused` test plus:
    /// - Payer pauses the stream resulting in a paused stream with total debt exceeding stream balance
    function test_GivenComponentPartiallyFundedAndPaused()
        public
        whenComponentNotNull
        whenComponentPartiallyFunded
        whenComponentPaused
    {
        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_INSOLVENT));
    }

    /// @dev Scenario for this test:
    /// - Payer creates a compensation component with one single component streaming USDT at a rate of `RATE_PER_SECOND` USDT/day
    /// - Payer cancels the stream resulting in a voided stream
    function test_GivenComponentCancelled() public whenComponentNotNull whenComponentCancelled {
        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        assertEq(actualStatus, uint8(Flow.Status.VOIDED));
    }
}
