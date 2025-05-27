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

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.getComponent({ componentId: 1 });
    }

    function test_GetComponent() public whenComponentNotNull {
        // Run the test
        Types.CompensationComponent memory component = compensationModule.getComponent({ componentId: 1 });

        // Assert the component fields
        assertEq(address(component.asset), address(usdt));
        assertEq(component.ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(component.streamId, 1);
        assertEq(uint8(component.componentType), uint8(Types.ComponentType.Payroll));
        assertEq(component.sender, address(space));
        assertEq(component.recipient, users.bob);
    }
}
