// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreateBatchCompensationPlan_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();
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

    function test_RevertWhen_EmptyRecipientsArray() external whenCallerContract whenCompliantSpace {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create an empty mock recipients array
        address[] memory recipients = new address[](0);

        // Create a mock compensation plan with one component
        Types.Component[][] memory components = new Types.Component[][](1);
        components[0] = new Types.Component[](1);
        components[0][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect the call to revert with the {InvalidEmptyRecipientsArray} error
        vm.expectRevert(Errors.InvalidEmptyRecipientsArray.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_DifferentRecipientsAndComponentsArraysLengths()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonEmptyRecipientsArray
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock recipients array with 2 recipients
        address[] memory recipients = new address[](2);
        recipients[0] = users.bob;
        recipients[1] = users.alice;

        // Create a mock compensation plan with ONLY one compensation plan
        Types.Component[][] memory components = new Types.Component[][](1);
        components[0] = new Types.Component[](1);
        components[0][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect the call to revert with the {InvalidRecipientsAndComponentsArraysLength} error
        vm.expectRevert(Errors.InvalidRecipientsAndComponentsArraysLength.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_RecipientZeroAddress()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonEmptyRecipientsArray
        whenRecipientsAndComponentsArraysHaveSameLength
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock recipients array with one zero-address recipient
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        // Create a mock compensation plan with ONLY one compensation plan
        Types.Component[][] memory components = new Types.Component[][](1);
        components[0] = new Types.Component[](1);
        components[0][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect the call to revert with the {InvalidZeroAddressRecipient} error
        vm.expectRevert(Errors.InvalidZeroAddressRecipient.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_AnyComponentArrayEmpty()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonEmptyRecipientsArray
        whenRecipientsAndComponentsArraysHaveSameLength
        whenNonZeroAddressRecipients
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock recipients array with one recipient
        address[] memory recipients = new address[](1);
        recipients[0] = users.bob;

        // Create a mock compensation plan with one empty component array
        Types.Component[][] memory components = new Types.Component[][](1);
        components[0] = new Types.Component[](0);

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect the call to revert with the {InvalidEmptyComponentsArray} error
        vm.expectRevert(Errors.InvalidEmptyComponentsArray.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_RevertWhen_AnyComponentHasZeroRatePerSecond()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonEmptyRecipientsArray
        whenRecipientsAndComponentsArraysHaveSameLength
        whenNonZeroAddressRecipients
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock recipients array with one recipient
        address[] memory recipients = new address[](1);
        recipients[0] = users.bob;

        // Create a mock compensation plan with one component with a zero rate per second
        Types.Component[][] memory components = new Types.Component[][](1);
        components[0] = new Types.Component[](1);
        components[0][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: UD21x18.wrap(0),
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect the call to revert with the {InvalidZeroRatePerSecond} error
        vm.expectRevert(Errors.InvalidZeroRatePerSecond.selector);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });
    }

    function test_CreateBatchCompensationPlan()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonEmptyRecipientsArray
        whenRecipientsAndComponentsArraysHaveSameLength
        whenNonZeroAddressRecipients
        whenNonZeroRatesPerSecond
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the mock recipients array
        address[] memory recipients = new address[](2);
        recipients[0] = users.bob;
        recipients[1] = users.alice;

        // Create two mock compensation plans with one component each
        Types.Component[][] memory components = new Types.Component[][](2);
        components[0] = new Types.Component[](1);
        components[0][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });
        components[1] = new Types.Component[](1);
        components[1][0] = Types.Component({
            componentType: Types.ComponentType.Payroll,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        // Create the calldata for the `createCompensationPlan` function call
        bytes memory data = abi.encodeWithSignature(
            "createBatchCompensationPlan(address[],(uint8,address,uint128,uint256)[][])", recipients, components
        );

        // Expect one {CompensationPlanCreated} event to be emitted for each recipient
        vm.expectEmit(address(compensationModule));
        emit ICompensationModule.CompensationPlanCreated({ compensationPlanId: 1, recipient: users.bob });
        emit ICompensationModule.CompensationPlanCreated({ compensationPlanId: 2, recipient: users.alice });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Assert the compensation plans were created correctly
        (address sender, address recipient, uint96 nextComponentId, Types.Component[] memory actualComponents) =
            compensationModule.getCompensationPlan(1);
        assertEq(sender, address(space));
        assertEq(recipient, users.bob);
        assertEq(nextComponentId, 1);
        assertEq(actualComponents.length, 1);
        assertEq(uint8(actualComponents[0].componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponents[0].asset), address(usdt));
        assertEq(actualComponents[0].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[0].streamId, 1);

        (sender, recipient, nextComponentId, actualComponents) = compensationModule.getCompensationPlan(2);
        assertEq(sender, address(space));
        assertEq(recipient, users.alice);
        assertEq(nextComponentId, 1);
        assertEq(actualComponents.length, 1);
        assertEq(uint8(actualComponents[0].componentType), uint8(Types.ComponentType.Payroll));
        assertEq(address(actualComponents[0].asset), address(usdt));
        assertEq(actualComponents[0].ratePerSecond.unwrap(), Constants.RATE_PER_SECOND.unwrap());
        assertEq(actualComponents[0].streamId, 2);
    }
}
