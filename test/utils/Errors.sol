// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                  STATION-REGISTRY
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `msg.sender` is not the station owner
    error CallerNotStationOwner();

    /*//////////////////////////////////////////////////////////////////////////
                                    CONTAINER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `msg.sender` is not the {Space} contract owner
    error CallerNotSpaceOwner();

    /// @notice Thrown when a native token (ETH) withdrawal fails
    error NativeWithdrawFailed();

    /// @notice Thrown when the available native token (ETH) balance is lower than
    /// the amount requested to be withdrawn
    error InsufficientNativeToWithdraw();

    /// @notice Thrown when the available ERC-20 token balance is lower than
    /// the amount requested to be withdrawn
    error InsufficientERC20ToWithdraw();

    /// @notice Thrown when the deposited ERC-20 token address is zero
    error InvalidAssetZeroAddress();

    /// @notice Thrown when the deposited ERC-20 token amount is zero
    error InvalidAssetZeroAmount();

    /// @notice Thrown when the ERC-721 token ID does not exist
    error ERC721NonexistentToken(uint256 tokenId);

    /// @notice Thrown when the balance of the sender is insufficient to perform an ERC-1155 transfer
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /// @notice Thrown when the provided `modules`, `values` or `data` arrays have different lengths
    error WrongArrayLengths();

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE-MANAGER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a {Space} tries to execute a method on a non-enabled module
    error ModuleNotEnabled(address module);

    /// @notice Thrown when an attempt is made to enable a non-allowlisted module on a {Space}
    error ModuleNotAllowlisted();

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE-KEEPER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the requested module to be allowlisted is not a valid non-zero code size contract
    error InvalidZeroCodeModule();

    /*//////////////////////////////////////////////////////////////////////////
                                PAYMENT-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Thrown when the caller is a contract that does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Thrown when the end time of a payment request is in the past
    error EndTimeInThePast();

    /// @notice Thrown when the start time is later than the end time
    error StartTimeGreaterThanEndTime();

    /// @notice Thrown when the payment amount set for a new paymentRequest is zero
    error ZeroPaymentAmount();

    /// @notice Thrown when the payment amount is less than the payment request value
    error PaymentAmountLessThanRequestedAmount(uint256 amount);

    /// @notice Thrown when a payment in the native token (ETH) fails
    error NativeTokenPaymentFailed();

    /// @notice Thrown when a linear or tranched stream is created with the native token as the payment asset
    error OnlyERC20StreamsAllowed();

    /// @notice Thrown when a payer attempts to pay a canceled payment request
    error RequestCanceled();

    /// @notice Thrown when a payer attempts to pay a completed payment request
    error RequestPaid();

    /// @notice Thrown when `msg.sender` is not the payment request recipient
    error OnlyRequestRecipient();

    /// @notice Thrown when the payment interval (endTime - startTime) is too short for the selected recurrence
    /// i.e. recurrence is set to weekly but interval is shorter than 1 week
    error PaymentIntervalTooShortForSelectedRecurrence();

    /// @notice Thrown when a tranched stream has a one-off recurrence type
    error TranchedStreamInvalidOneOffRecurence();

    /// @notice Thrown when the caller is not the initial stream sender
    error OnlyInitialStreamSender(address initialSender);

    /// @notice Thrown when the payment request is null
    error NullRequest();

    /// @notice Thrown when the recipient address is the zero address
    error InvalidZeroAddressRecipient();

    /*//////////////////////////////////////////////////////////////////////////
                                    STREAM-MANAGER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is not the broker admin
    error OnlyBrokerAdmin();

    /// @notice Thrown when `msg.sender` is not the stream's sender
    error SablierV2Lockup_Unauthorized(uint256 streamId, address caller);

    /*//////////////////////////////////////////////////////////////////////////
                                      OWNABLE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to transfer ownership to the zero address
    error InvalidOwnerZeroAddress();

    /// @notice Thrown when `msg.sender` is not the contract owner
    error Unauthorized();

    /// @notice Thrown when `msg.sender` is not authorized to perform an operation
    error OwnableUnauthorizedAccount(address account);

    /*//////////////////////////////////////////////////////////////////////////
                                THIRDWEB - PERMISSIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The `account` is missing a role.
    error PermissionsUnauthorizedAccount(address account, bytes32 neededRole);
}
