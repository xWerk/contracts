// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { CreateCompensationPlan_Integration_Shared_Test } from "./createCompensationPlan.t.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";

abstract contract StatusOfComponent_Integration_Shared_Test is
    Integration_Test,
    CreateCompensationPlan_Integration_Shared_Test
{
    function setUp() public virtual override(Integration_Test, CreateCompensationPlan_Integration_Shared_Test) {
        CreateCompensationPlan_Integration_Shared_Test.setUp();
    }

    modifier whenComponentNotNull() {
        // Create a mock compensation plan with 1 component
        Types.Component[] memory expectedComponents = createMockCompensationPlan(Types.ComponentType.Payroll);

        // Create the calldata for the `createCompensationPlan` function call with Bob as the recipient
        bytes memory data = abi.encodeWithSignature(
            "createCompensationPlan(address,(uint8,address,uint128,uint256)[])", users.bob, expectedComponents
        );

        // Create the compensation plan
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }

    modifier whenComponentPartiallyFunded() {
        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 10e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSignature("depositToComponent(uint256,uint96,uint128)", 1, 0, 10e6);

        // Fund the compensation plan with only 10 USDT which will be streamed in ~3 hours (at a rate of 86.4 USDT/day)
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Fast forward the time by 3 hours
        // After ~3 hours, the stream will be insolvent because all its balance will be fully streamed
        vm.warp(block.timestamp + 3 hours);

        _;
    }

    modifier whenComponentPaused() {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSignature("pauseComponent(uint256,uint96)", 1, 0);

        // Pause the compensation component stream
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }

    modifier whenComponentCancelled() {
        // Create the calldata for the `cancelComponent` call
        bytes memory data = abi.encodeWithSignature("cancelComponent(uint256,uint96)", 1, 0);

        // Cancel the compensation component stream
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }
}
