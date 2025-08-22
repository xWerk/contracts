// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

contract createComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();
    }

    function test_RevertWhen_RecipientZeroAddress() external whenCallerContract {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation component with 1 component
        Types.CompensationComponent memory initialComponent = createMockComponent(Types.ComponentType.Payroll);

        // Create the calldata for the `createComponent` function call
        bytes memory data = abi.encodeWithSignature(
            "createComponent(address,uint128,uint8,address)",
            address(0),
            initialComponent.ratePerSecond,
            uint8(initialComponent.componentType),
            address(initialComponent.asset)
        );

        // Expect the call to revert with the {InvalidZeroAddressRecipient} error
        vm.expectRevert(Errors.InvalidZeroAddressRecipient.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_ZeroRatePerSecond() external whenNonZeroAddressRecipient {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation component with 1 component
        Types.CompensationComponent memory initialComponent = createMockComponent(Types.ComponentType.Payroll);

        // Set the rate per second to zero
        initialComponent.ratePerSecond = UD21x18.wrap(0);

        // Create the calldata for the `createComponent` function call
        bytes memory data = abi.encodeWithSignature(
            "createComponent(address,uint128,uint8,address)",
            users.bob,
            initialComponent.ratePerSecond,
            uint8(initialComponent.componentType),
            address(initialComponent.asset)
        );

        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_createComponent() external whenNonZeroAddressRecipient whenNonZeroRatePerSecond {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation component with an initial Payroll component
        Types.CompensationComponent memory initialComponent = createMockComponent(Types.ComponentType.Payroll);

        // Create the calldata for the `createComponent` function call
        bytes memory data = abi.encodeWithSignature(
            "createComponent(address,uint128,uint8,address)",
            users.bob,
            initialComponent.ratePerSecond,
            uint8(initialComponent.componentType),
            address(initialComponent.asset)
        );

        // Expect the {ComponentCreated} event to be emitted
        vm.expectEmit(address(compensationModule));
        emit ICompensationModule.ComponentCreated({ componentId: 1, recipient: users.bob, streamId: 1 });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Assert the compensation component was created
        Types.CompensationComponent memory actualComponent = compensationModule.getComponent(1);
        assertEq(uint8(actualComponent.componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponent.asset), address(usdt));
        assertEq(actualComponent.ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponent.streamId, 1);
    }
}
