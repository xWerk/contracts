// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { Constants } from "test/utils/Constants.sol";

contract GetComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.getComponent(1, 0);
    }

    function test_GetComponent() public whenComponentNotNull {
        // Run the test
        Types.Component memory component = compensationModule.getComponent(1, 0);

        // Assert the component is not null
        assertEq(address(component.asset), address(usdt));
        assertEq(component.ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(component.streamId, 1);
    }
}
