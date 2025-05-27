// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";

contract AdjustComponentRatePerSecond_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public virtual override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.adjustComponentRatePerSecond({ componentId: 1, newRatePerSecond: UD21x18.wrap(0.002e18) });
    }

    function test_RevertWhen_CallerNotComponentSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentSender} error
        vm.expectRevert(Errors.OnlyComponentSender.selector);

        // Run the test
        compensationModule.adjustComponentRatePerSecond({ componentId: 1, newRatePerSecond: UD21x18.wrap(0.002e18) });
    }

    function test_RevertWhen_InvalidZeroRatePerSecond()
        public
        whenComponentNotNull
        whenCallerComponentSender(users.eve)
    {
        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Create the calldata for the `adjustComponentRatePerSecond` call
        bytes memory data =
            abi.encodeWithSelector(compensationModule.adjustComponentRatePerSecond.selector, 1, 0, UD21x18.wrap(0));

        // Run the test by executing the `adjustComponentRatePerSecond` method from Eve's Space which is the compensation component sender
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_AdjustComponentRatePerSecond()
        public
        whenComponentNotNull
        whenCallerComponentSender(users.eve)
        whenNonZeroRatePerSecond
    {
        // Create the calldata for the `adjustComponentRatePerSecond` call
        bytes memory data =
            abi.encodeWithSelector(compensationModule.adjustComponentRatePerSecond.selector, 1, UD21x18.wrap(0.002e18));

        // Expect the {ComponentRatePerSecondAdjusted} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentRatePerSecondAdjusted({
            componentId: 1,
            newRatePerSecond: UD21x18.wrap(0.002e18)
        });

        // Run the test by executing the `adjustComponentRatePerSecond` method from Eve's Space which is the compensation component sender
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the actual compensation component
        Types.CompensationComponent memory actualComponent = compensationModule.getComponent(1);

        // Assert the actual and expected component fields
        assertEq(actualComponent.sender, address(space));
        assertEq(actualComponent.recipient, users.bob);
        assertEq(actualComponent.streamId, 1);
        assertEq(uint8(actualComponent.componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponent.asset), address(usdt));
        assertEq(actualComponent.ratePerSecond.unwrap(), UD21x18.wrap(0.002e18).unwrap());
    }
}
