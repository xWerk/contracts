// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract RefundComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.refundComponent({ componentId: 1 });
    }

    function test_RevertWhen_OnlyComponentSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentSender} error
        vm.expectRevert(Errors.OnlyComponentSender.selector);

        // Run the test
        compensationModule.refundComponent({ componentId: 1 });
    }

    function test_RefundComponent() public whenComponentNotNull whenCallerComponentSender(users.eve) {
        // Cache the balance of the {Space} contract before the refund
        uint256 balanceOfSpaceBefore = usdt.balanceOf(address(space));

        // Fund the compensation component first

        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 100e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSignature("depositToComponent(uint256,uint128)", 1, 100e6);

        // Fund the compensation component
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Refund the entire amount deposited before

        // Create the calldata for the `refundComponent` call
        data = abi.encodeWithSelector(compensationModule.refundComponent.selector, 1);

        // Expect the {ComponentRefunded} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentRefunded({ componentId: 1 });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Cache the balance of the {Space} contract after the refund
        uint256 balanceOfSpaceAfter = usdt.balanceOf(address(space));

        // Assert the balance of the {Space} contract has increased by the amount of the refund
        // @todo: fix this test once the Sablier Flow PR is merged
        /* assertEq(balanceOfSpaceAfter - balanceOfSpaceBefore, 100e6); */
    }
}
