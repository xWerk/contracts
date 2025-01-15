// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IWerkSubdomainRegistry } from "./interfaces/IWerkSubdomainRegistry.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Ownable } from "./../../abstracts/Ownable.sol";
import { ISubdomainPricer } from "./interfaces/ISubdomainPricer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title WerkSubdomainRegistrar
/// @notice This is a fork implementation of the L2Registrar contract created by NameStone
/// @dev See the initial implementation here: https://github.com/namestonehq/durin/blob/main/src/L2Registrar.sol
contract WerkSubdomainRegistrar is Ownable {
    /// @notice Emitted when a new name is registered
    /// @param label The registered label (e.g. "name" in "name.werk.eth")
    /// @param owner The owner of the newly registered name
    event NameRegistered(string indexed label, address indexed owner);

    /// @notice Emitted when a subdomain is reserved
    /// @param label The reserved label (e.g. "name" in "name.werk.eth")
    /// @param owner The owner of the reserved subdomain
    /// @param expiresAt The timestamp at which the reservation expires
    event SubdomainReserved(string indexed label, address indexed owner, uint40 expiresAt);

    /// @notice Thrown when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Thrown when the caller is a contract that does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Thrown when the subdomain has already been reserved
    error AlreadyReserved(uint40 expiresAt);

    /// @notice Thrown when the reservation has expired
    error ReservationExpired();

    /// @notice Thrown when there is no reservation found for the given label
    error ReservationNotFound();

    /// @notice Thrown when the caller is not the owner of the reservation
    error NotReservationOwner(uint40 expiresAt);

    /// @notice Thrown when a native token payment fails
    error NativeTokenPaymentFailed();

    /// @dev The address of the native token (ETH) following the ERC-7528 standard
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Reference to the target registry contract
    IWerkSubdomainRegistry public immutable registry;

    /// @notice Reference to the subdomain pricer contract
    ISubdomainPricer public pricer;

    /// @notice The chainId for the current chain
    uint256 public chainId;

    /// @notice The coinType for the current chain (ENSIP-11)
    uint256 public immutable coinType;

    /// @notice Enum representing the different values describing a reservation
    /// @param owner The address that owns the reservation
    /// @param expiresAt The timestamp at which the reservation expires
    struct Reservation {
        address owner;
        uint40 expiresAt;
    }

    /// @notice Mapping storing the reservations for each label
    mapping(bytes32 => Reservation) public reservations;

    /// @notice Initializes the registrar with a registry contract
    /// @param _registry Address of the L2Registry contract
    /// @param _owner Address of the registrar owner
    constructor(IWerkSubdomainRegistry _registry, address _owner) Ownable(_owner) {
        assembly {
            sstore(chainId.slot, chainid())
        }

        coinType = (0x80000000 | chainId) >> 0;
        registry = _registry;
    }

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        // Checks: the sender is a valid non-zero code size contract
        if (msg.sender.code.length == 0) {
            revert SpaceZeroCodeSize();
        }

        // Checks: the sender implements the ERC-165 interface required by {ISpace}
        bytes4 interfaceId = type(ISpace).interfaceId;
        if (!ISpace(msg.sender).supportsInterface(interfaceId)) revert SpaceUnsupportedInterface();
        _;
    }

    /// @notice Checks if a given label is available for registration
    /// @param label The label to check availability for
    /// @return available True if the label can be registered, false if already taken
    /// @dev Uses try-catch to handle the ERC721NonexistentToken error
    function available(string memory label) external view returns (bool) {
        bytes32 labelhash = keccak256(bytes(label));
        uint256 tokenId = uint256(labelhash);

        try registry.ownerOf(tokenId) {
            return false;
        } catch {
            return true;
        }
    }

    /// @notice Reserves a name for 30 minutes for a given address
    /// @param label The label to reserve (e.g. "name" for "name.werk.eth")
    function reserve(string memory label) external onlySpace {
        // Hash the label to get the labelhash
        bytes32 labelhash = keccak256(bytes(label));

        // Retrieve the reservation for the label to check if it has already been reserved
        Reservation memory reservation = reservations[labelhash];

        // Check if there is an existing reservation for this label and if it's still valid (not expired)
        if (reservation.owner != address(0) && reservation.expiresAt > block.timestamp) {
            revert AlreadyReserved({ expiresAt: reservation.expiresAt });
        }

        // Create a new reservation for the label
        uint40 expiresAt = uint40(block.timestamp + 30 minutes);
        reservations[labelhash] = Reservation({ owner: msg.sender, expiresAt: expiresAt });

        // Log the reservation event
        emit SubdomainReserved({ label: label, owner: msg.sender, expiresAt: expiresAt });
    }

    /// @notice Registers a new name for free
    ///
    /// Requirements:
    /// - `msg.sender` must be a contract implementing the {ISpace} interface
    /// - `msg.sender` must have a valid reservation for the label
    ///
    /// @param label The label to register (e.g. "name" for "name.werk.eth")
    /// @param owner The address that will own the name
    function register(string memory label, address owner) external onlySpace {
        // Hash the label to get the labelhash
        bytes32 labelhash = keccak256(bytes(label));

        // Retrieve the reservation for the label to check if it has already been reserved
        Reservation memory reservation = reservations[labelhash];

        // Check if there is an existing reservation for this label and if it's still valid (not expired)
        if (reservation.owner == address(0)) {
            revert ReservationNotFound();
        }

        // Check if the reservation is still valid
        if (reservation.expiresAt < block.timestamp) {
            revert ReservationExpired();
        }

        // Check if `msg.sender` is the owner of the reservation
        if (reservation.owner != msg.sender) {
            revert NotReservationOwner({ expiresAt: reservation.expiresAt });
        }

        // Retrieve the price details from the pricer contract
        (address asset, uint256 price) = ISubdomainPricer(pricer).getPriceDetails();

        // If there is a price to pay, the `msg.sender` needs to pay for the registration
        if (price > 0) {
            if (asset == NATIVE_TOKEN) {
                (bool success,) = msg.sender.call{ value: price }("");
                if (!success) revert NativeTokenPaymentFailed();
            } else {
                IERC20(asset).transferFrom(msg.sender, address(this), price);
            }
        }

        // Convert the address to bytes
        bytes memory addr = abi.encodePacked(owner);

        // Set the forward address for the current chain. This is needed for reverse resolution.
        // E.g. if this contract is deployed to Base, set an address for chainId 8453 which is
        // coinType 2147492101 according to ENSIP-11.
        registry.setAddr(labelhash, coinType, addr);

        // Set the forward address for mainnet ETH (coinType 60) for easier debugging.
        registry.setAddr(labelhash, 60, addr);

        // Register the name in the L2 registry
        registry.register(label, owner);

        // Log the registration event
        emit NameRegistered(label, owner);
    }

    /// @notice Withdraws an ERC-20 token from the Registrar
    /// @param asset The ERC-20 token to withdraw
    /// @param amount The amount of tokens to withdraw
    function withdrawERC20(IERC20 asset, uint256 amount) public onlyOwner {
        // Withdraw by transferring the `amount` to the owner
        asset.transfer(owner, amount);
    }

    /// @notice Withdraws native tokens (ETH) from the Registrar
    /// @param amount The amount of native tokens to withdraw
    function withdrawNative(uint256 amount) public onlyOwner {
        // Interactions: withdraw by transferring the `amount` to the owner
        (bool success,) = owner.call{ value: amount }("");
        // Revert if the call failed
        if (!success) revert NativeTokenPaymentFailed();
    }
}
