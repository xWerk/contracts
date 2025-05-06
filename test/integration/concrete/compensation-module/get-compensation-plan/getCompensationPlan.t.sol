// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CreateCompensationPlan_Integration_Shared_Test } from "test/integration/shared/createCompensationPlan.t.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

contract GetCompensationPlan_Integration_Concrete_Test is CreateCompensationPlan_Integration_Shared_Test {
    function setUp() public override {
        CreateCompensationPlan_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_CompensationPlanNull() public {
        // Make Bob the caller in this test suite which is an EOA
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {CompensationPlanNull} error
        vm.expectRevert(Errors.CompensationPlanNull.selector);

        // Run the test
        compensationModule.getCompensationPlan(1);
    }

    function test_GetCompensationPlan() public whenPlanNotNull {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a mock compensation plan with 1 component
        Types.Component[] memory expectedComponents = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call with Bob as the recipient
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, expectedComponents
        );

        // Create the compensation plan
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation plan
        (address sender, address recipient, uint96 numberOfComponents, Types.Component[] memory actualComponents) =
            compensationModule.getCompensationPlan(1);

        // Assert the compensation plan fields
        assertEq(sender, address(space));
        assertEq(recipient, users.bob);
        assertEq(numberOfComponents, 1);
        assertEq(actualComponents.length, expectedComponents.length);

        // Decode the first component of the compensation plan
        (uint8 componentType, address asset, UD21x18 ratePerSecond, uint256 streamId) =
            abi.decode(abi.encode(actualComponents[0]), (uint8, address, UD21x18, uint256));

        // Assert the component fields
        assertEq(componentType, uint8(expectedComponents[0].componentType));
        assertEq(asset, address(expectedComponents[0].asset));
        assertEq(ratePerSecond.unwrap(), expectedComponents[0].ratePerSecond.unwrap());

        // Component's stream ID must be 1 as the Sablier Flow stream gets created when the component is created
        assertEq(streamId, 1);
    }
}
