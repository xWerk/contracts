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

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.adjustComponentRatePerSecond(1, 0, UD21x18.wrap(0.002e18));
    }

    function test_RevertWhen_CallerNotCompensationPlanSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanSender} error
        vm.expectRevert(Errors.OnlyCompensationPlanSender.selector);

        // Run the test
        compensationModule.adjustComponentRatePerSecond(1, 0, UD21x18.wrap(0.002e18));
    }

    function test_RevertWhen_InvalidZeroRatePerSecond() public whenComponentNotNull whenCallerCompensationPlanSender {
        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Create the calldata for the `adjustComponentRatePerSecond` call
        bytes memory data =
            abi.encodeWithSelector(compensationModule.adjustComponentRatePerSecond.selector, 1, 0, UD21x18.wrap(0));

        // Run the test by executing the `adjustComponentRatePerSecond` method from Eve's Space which is the compensation plan sender
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_AdjustComponentRatePerSecond()
        public
        whenComponentNotNull
        whenCallerCompensationPlanSender
        whenNonZeroRatePerSecond
    {
        // Create the calldata for the `adjustComponentRatePerSecond` call
        bytes memory data = abi.encodeWithSelector(
            compensationModule.adjustComponentRatePerSecond.selector, 1, 0, UD21x18.wrap(0.002e18)
        );

        // Expect the {ComponentRatePerSecondAdjusted} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentRatePerSecondAdjusted(1, 0, UD21x18.wrap(0.002e18));

        // Run the test by executing the `adjustComponentRatePerSecond` method from Eve's Space which is the compensation plan sender
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Create a mock compensation plan with 1 component to help us assert the compensation plan fields
        Types.Component memory expectedComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Retrieve the compensation plan
        (address sender, address recipient, uint96 numberOfComponents, Types.Component[] memory actualComponents) =
            compensationModule.getCompensationPlan(1);

        // Assert the compensation plan fields
        assertEq(sender, address(space));
        assertEq(recipient, users.bob);
        assertEq(numberOfComponents, 1);
        assertEq(actualComponents.length, 1);

        // Decode the first component of the compensation plan
        (uint8 componentType, address asset, UD21x18 ratePerSecond,) =
            abi.decode(abi.encode(actualComponents[0]), (uint8, address, UD21x18, uint256));

        // Assert the component fields
        assertEq(componentType, uint8(expectedComponent.componentType));
        assertEq(asset, address(expectedComponent.asset));
        assertEq(ratePerSecond.unwrap(), UD21x18.wrap(0.002e18).unwrap());
    }
}
