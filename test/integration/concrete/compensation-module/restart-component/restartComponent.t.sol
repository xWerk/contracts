// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { Constants } from "test/utils/Constants.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

contract RestartComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.restartComponent(1, 0, Constants.RATE_PER_SECOND);
    }

    function test_RevertWhen_OnlyCompensationPlanSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanSender} error
        vm.expectRevert(Errors.OnlyCompensationPlanSender.selector);

        // Run the test
        compensationModule.restartComponent(1, 0, Constants.RATE_PER_SECOND);
    }

    function test_RevertWhen_InvalidZeroRatePerSecond() public whenComponentNotNull whenCallerCompensationPlanSender {
        // Create the calldata for the `restartComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.restartComponent.selector, 1, 0, UD21x18.wrap(0));

        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RestartComponent() public whenComponentNotNull whenCallerCompensationPlanSender {
        // Pause the component stream first
        bytes memory data = abi.encodeWithSelector(compensationModule.pauseComponent.selector, 1, 0);
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Create the calldata for the `restartComponent` call
        data = abi.encodeWithSelector(compensationModule.restartComponent.selector, 1, 0, Constants.RATE_PER_SECOND);

        // Expect the {CompensationComponentRestarted} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentRestarted({
            compensationPlanId: 1,
            componentId: 0,
            newRatePerSecond: Constants.RATE_PER_SECOND
        });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation plan
        uint8 actualStatus = uint8(compensationModule.statusOfComponent(1, 0));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be solvent as the total debt is not exceeding the stream balance
        assertEq(actualStatus, uint8(Flow.Status.STREAMING_SOLVENT));
    }
}
