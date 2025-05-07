// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract DepositToComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    uint128 constant DEPOSIT_AMOUNT = 10e6;

    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.depositToComponent(1, 0, DEPOSIT_AMOUNT);
    }

    function test_RevertWhen_InvalidZeroDepositAmount() public whenComponentNotNull {
        // Expect the call to revert with the {InvalidZeroDepositAmount} error
        vm.expectRevert(Errors.InvalidZeroDepositAmount.selector);

        // Run the test
        compensationModule.depositToComponent(1, 0, 0);
    }

    function test_DepositToComponent() public whenComponentNotNull {
        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 10e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSelector(compensationModule.depositToComponent.selector, 1, 0, DEPOSIT_AMOUNT);

        // Expect the {CompensationComponentDeposited} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentDeposited(1, 0, DEPOSIT_AMOUNT);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation plan
        Types.Component memory component = compensationModule.getComponent(1, 0);

        // Retrieve the compensation plan component stream
        Flow.Stream memory stream = compensationModule.getComponentStream(component.streamId);

        // Assert the actual and expected stream balance
        assertEq(stream.balance, DEPOSIT_AMOUNT);
    }
}
