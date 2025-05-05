// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CreateCompensationPlan_Integration_Shared_Test } from "../../../shared/createCompensationPlan.t.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { Events } from "./../../../../utils/Events.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "./../../../../utils/Constants.sol";

contract CreateCompensationPlan_Integration_Concrete_Test is CreateCompensationPlan_Integration_Shared_Test {
    function setUp() public override {
        CreateCompensationPlan_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_CallerNotSpace() external {
        // Make Bob the caller in this test suite which is an EOA
        vm.startPrank({ msgSender: users.bob });

        // Create a mock compensation plan with 1 component
        Types.Component[] memory components = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Expect the call to revert with the {SpaceZeroCodeSize} error
        vm.expectRevert(Errors.SpaceZeroCodeSize.selector);

        // Run the test
        compensationModule.createCompensationPlan({ recipient: users.bob, components: components });
    }

    function test_RevertWhen_NonCompliantSpace() external whenCallerContract {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component[] memory components = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, components
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
        Types.Component[] memory components = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", address(0), components
        );

        // Expect the call to revert with the {InvalidZeroAddressRecipient} error
        vm.expectRevert(Errors.InvalidZeroAddressRecipient.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_EmptyComponentsArray()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroAddressRecipient
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component[] memory components = new Types.Component[](0);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, components
        );

        // Expect the call to revert with the {InvalidEmptyComponentsArray} error
        vm.expectRevert(Errors.InvalidEmptyComponentsArray.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_ZeroRatePerSecond()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroAddressRecipient
        whenNonZeroComponentsArray
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component[] memory components = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Set the rate per second to zero
        components[0].ratePerSecond = UD21x18.wrap(0);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, components
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
        whenNonZeroComponentsArray
        whenNonZeroRatePerSecond
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 3 components
        Types.Component[] memory components = new Types.Component[](3);
        components[0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });
        components[1] = Types.Component({
            componentType: Types.ComponentType.Payout,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });
        components[2] = Types.Component({
            componentType: Types.ComponentType.ESOP,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, components
        );

        // Expect the {CompensationPlanCreated} event to be emitted
        vm.expectEmit(address(compensationModule));
        emit Events.CompensationPlanCreated({ compensationPlanId: 1, recipient: users.bob });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Assert the compensation plan was created
        (address sender, address recipient, uint96 nextComponentId, Types.Component[] memory actualComponents) =
            compensationModule.getCompensationPlan(1);
        assertEq(sender, address(space));
        assertEq(recipient, users.bob);
        assertEq(nextComponentId, 3);

        // Assert the components were created correctly
        assertEq(actualComponents.length, 3);
        assertEq(uint8(actualComponents[0].componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponents[0].asset), address(usdt));
        assertEq(actualComponents[0].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[0].streamId, 1);

        assertEq(uint8(actualComponents[1].componentType), uint8(Types.ComponentType.Payout));
        assertEq(address(actualComponents[1].asset), address(usdt));
        assertEq(actualComponents[1].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[1].streamId, 2);

        assertEq(uint8(actualComponents[2].componentType), uint8(Types.ComponentType.ESOP));
        assertEq(address(actualComponents[2].asset), address(usdt));
        assertEq(actualComponents[2].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[2].streamId, 3);
    }
}
