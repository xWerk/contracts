// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TransferFrom_Integration_Shared_Test } from "../../../shared/transferFrom.t.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Types } from "./../../../../../src/modules/payment-module/libraries/Types.sol";

contract TransferFrom_Integration_Concret_Test is TransferFrom_Integration_Shared_Test {
    function setUp() public virtual override {
        TransferFrom_Integration_Shared_Test.setUp();
    }

    /* function test_RevertWhen_TokenDoesNotExist() external {
        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Expect the call to revert with the {ERC721NonexistentToken} error
        vm.expectRevert(abi.encodeWithSelector(Errors.ERC721NonexistentToken.selector, 99));

        // Run the test
        invoiceModul.transferFrom({ from: address(space), to: users.eve, tokenId: 99 });
    }

    function test_TransferFrom_PaymentMethodStream() external whenTokenExists {
        uint256 paymentRequestId = 4;
        uint256 streamId = 1;

        // Make Bob the payer for the payment request
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].payment.amount });

        // Pay the payment request
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].payment.amount }({ requestId: paymentRequestId });

        // Simulate the passage of time so that the maximum withdrawable amount is non-zero
        vm.warp(block.timestamp + 5 weeks);

        // Store Eve's space balance before withdrawing the USDT tokens
        uint256 balanceOfBefore = usdt.balanceOf(address(space));

        // Get the maximum withdrawable amount from the stream before transferring the stream NFT
        uint128 maxWithdrawableAmount =
            paymentModule.withdrawableAmountOf({ streamType: Types.Method.LinearStream, streamId: streamId });

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Approve the {PaymentModule} to transfer the `streamId` stream on behalf of the Eve's space
        sablierV2LockupLinear.approve({ to: address(paymentModule), tokenId: streamId });

        // Run the test
        paymentModule.transferFrom({ from: address(space), to: users.eve, tokenrequestId: paymentRequestId });

        // Assert the current and expected Eve's space USDT balance
        assertEq(balanceOfBefore + maxWithdrawableAmount, usdt.balanceOf(address(space)));

        // Assert the current and expected owner of the payment request NFT
        assertEq(paymentModule.ownerOf({ tokenrequestId: paymentRequestId }), users.eve);

        // Assert the current and expected owner of the payment request stream NFT
        assertEq(sablierV2LockupLinear.ownerOf({ tokenId: streamId }), users.eve);
    }

    function test_TransferFrom_PaymentTransfer() external whenTokenExists {
        uint256 paymentRequestId = 1;

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Run the test
        paymentModule.transferFrom({ from: address(space), to: users.eve, tokenrequestId: paymentRequestId });

        // Assert the current and expected owner of the payment request NFT
        assertEq(paymentModule.ownerOf({ tokenrequestId: paymentRequestId }), users.eve);
    } */
}
