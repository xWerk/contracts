// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";

contract RefundComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.refundComponent(1, 0);
    }

    function test_RevertWhen_OnlyCompensationPlanSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanSender} error
        vm.expectRevert(Errors.OnlyCompensationPlanSender.selector);

        // Run the test
        compensationModule.refundComponent(1, 0);
    }

    function test_RefundComponent() public whenComponentNotNull {
        // Cache the balance of the {Space} contract before the refund
        uint256 balanceOfSpaceBefore = usdt.balanceOf(address(space));

        // Fund the compensation plan first

        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 100e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSignature("depositToComponent(uint256,uint96,uint128)", 1, 0, 100e6);

        // Fund the compensation plan
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Refund the entire amount deposited before

        // Create the calldata for the `refundComponent` call
        data = abi.encodeWithSelector(compensationModule.refundComponent.selector, 1, 0);

        // Expect the {CompensationComponentRefunded} event to be emitted
        vm.expectEmit();
        emit CompensationComponentRefunded(1, 0);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Cache the balance of the {Space} contract after the refund
        uint256 balanceOfSpaceAfter = usdt.balanceOf(address(space));

        // Assert the balance of the {Space} contract has increased by the amount of the refund
        // @todo: fix this test once the Sablier Flow PR is merged
        /* assertEq(balanceOfSpaceAfter - balanceOfSpaceBefore, 100e6); */
    }
}
