// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../libraries/Types.sol";

/// @title IPaymentModule
/// @notice Contract module that provides functionalities to issue on-chain payment requests
interface IPaymentModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a payment request is created
    /// @param requestId The ID of the payment request
    /// @param recipient The address receiving the payment
    /// @param startTime The timestamp when the payment request takes effect
    /// @param endTime The timestamp by which the payment request must be paid
    /// @param config Struct representing the payment details associated with the payment request
    event RequestCreated(
        uint256 indexed requestId, address indexed recipient, uint40 startTime, uint40 endTime, Types.Config config
    );

    /// @notice Emitted when a payment is made for a payment request
    /// @param requestId The ID of the payment request
    /// @param payer The address of the payer
    /// @param config Struct representing the payment details
    event RequestPaid(uint256 indexed requestId, address indexed payer, Types.Config config);

    /// @notice Emitted when a payment request is canceled
    /// @param requestId The ID of the payment request
    event RequestCanceled(uint256 indexed requestId);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the details of the `id` payment request
    /// @param requestId The ID of the payment request for which to get the details
    function getRequest(uint256 requestId) external view returns (Types.PaymentRequest memory request);

    /// @notice Retrieves the status of the `requestId` payment request
    /// @param requestId The ID of the payment request for which to retrieve the status
    function statusOf(uint256 requestId) external view returns (Types.Status status);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new payment request
    ///
    /// Requirements:
    /// - `msg.sender` must be a contract implementing the {ISpace} interface
    ///
    /// Notes:
    /// - `recipient` is not checked because the call is enforced to be made through a {Space} contract
    ///
    /// @param request request The details of the payment request following the {PaymentRequest} struct format
    /// @return requestId The on-chain ID of the payment request
    function createRequest(Types.PaymentRequest calldata request) external returns (uint256 requestId);

    /// @notice Pays a transfer-based payment request
    ///
    /// Notes:
    /// - `msg.sender` is enforced to be a specific payer address
    ///
    /// @param requestId The ID of the payment request to pay
    function payRequest(uint256 requestId) external payable;

    /// @notice Cancels the `id` payment request
    ///
    /// Notes:
    /// - A transfer-based payment request can be canceled only by its creator (recipient)
    /// - A linear/tranched stream-based payment request can be canceled by its creator only if its
    /// status is `Pending`; otherwise only the stream sender can cancel it
    /// - if the payment request has a linear or tranched stream payment method, the streaming flow will be
    /// stopped and the remaining funds will be refunded to the stream payer
    ///
    /// Important:
    /// - if the payment request has a linear or tranched stream payment method, the portion that has already
    /// been streamed is NOT automatically transferred
    ///
    /// @param requestId The ID of the payment request
    function cancelRequest(uint256 requestId) external;

    /// @notice Withdraws the maximum withdrawable amount from the stream associated with the `id` payment request
    ///
    /// Notes:
    /// - reverts if `msg.sender` is not the stream recipient
    /// - reverts if the payment method of the `id` payment request is not linear or tranched stream
    ///
    /// @param requestId The ID of the payment request
    function withdrawRequestStream(uint256 requestId) external returns (uint128 withdrawnAmount);
}
