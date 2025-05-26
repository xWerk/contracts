// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreateCompensationPlan_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotSpace() external {
        // Make Bob the caller in this test suite which is an EOA
        vm.startPrank({ msgSender: users.bob });

        // Create a mock compensation plan with 1 component
        Types.Component memory initialComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Expect the call to revert with the {SpaceZeroCodeSize} error
        vm.expectRevert(Errors.SpaceZeroCodeSize.selector);

        // Run the test
        compensationModule.createCompensationPlan({ recipient: users.bob, component: initialComponent });
    }

    function test_RevertWhen_NonCompliantSpace() external whenCallerContract {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component memory initialComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256))", users.bob, initialComponent
        );

        // Expect the call to revert with the {SpaceUnsupportedInterface} error
        vm.expectRevert(Errors.SpaceUnsupportedInterface.selector);

        // Run the test
        mockNonCompliantSpace.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_RecipientZeroAddress() external whenCallerContract whenCompliantSpace {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component memory initialComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256))", address(0), initialComponent
        );

        // Expect the call to revert with the {InvalidZeroAddressRecipient} error
        vm.expectRevert(Errors.InvalidZeroAddressRecipient.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_ZeroRatePerSecond()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroAddressRecipient
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component memory initialComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Set the rate per second to zero
        initialComponent.ratePerSecond = UD21x18.wrap(0);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256))", users.bob, initialComponent
        );

        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_CreateCompensationPlan()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroAddressRecipient
        whenNonZeroRatePerSecond
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with an initial Payroll component
        Types.Component memory initialComponent = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256))", users.bob, initialComponent
        );

        // Expect the {CompensationPlanCreated} event to be emitted
        vm.expectEmit(address(compensationModule));
        emit ICompensationModule.CompensationPlanCreated({ compensationPlanId: 1, recipient: users.bob, streamId: 1 });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Assert the compensation plan was created
        (address sender, address recipient, uint96 nextComponentId, Types.Component[] memory actualComponents) =
            compensationModule.getCompensationPlan(1);
        assertEq(sender, address(space));
        assertEq(recipient, users.bob);
        assertEq(nextComponentId, 1);

        // Assert the initial component was created correctly
        assertEq(actualComponents.length, 1);
        assertEq(uint8(actualComponents[0].componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponents[0].asset), address(usdt));
        assertEq(actualComponents[0].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[0].streamId, 1);
    }
}
