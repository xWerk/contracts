// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Ownable } from "./../../abstracts/Ownable.sol";

/// @notice Minimal ENSIP-11 interface for resolvers that support setting multi-coin address records
interface IAddrResolver {
    function setAddr(bytes32 node, uint256 coinType, bytes calldata value) external;
}

/// @title WerkRegistrar
/// @notice Registrar for subnames under `werk.eth`, enforcing one subname per Werk space
contract WerkRegistrar is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice ENSIP-19 default coin type — resolves for all EVM chains unless overridden
    uint256 public constant COIN_TYPE_DEFAULT = 1 << 31;

    /// @notice ENSv2 registry that holds all subnames under `werk.eth`
    IPermissionedRegistry public immutable WERK_REGISTRY;

    /// @notice Shared resolver used for all werk subnames
    address public immutable RESOLVER;

    /// @notice Namehash of `werk.eth`, used as parent node for subname nodes
    bytes32 public immutable WERK_NODE;

    /// @notice Maps a Werk space to its claimed label hash
    // Note: helps to enforce once subname per space
    mapping(address space => bytes32 labelHash) public spaceToLabel;

    /// @notice Maps a label hash to the Werk space that claimed it
    // Note: Ownership querying from the registry requires two calls
    // Keeping this mapping will provide cheaper reads (2 external calls vs 1 SLOAD)
    mapping(bytes32 labelHash => address space) public labelToSpace;

    /// @notice Reservation details for a label
    /// @param owner The address that owns the reservation
    /// @param expiresAt The timestamp at which the reservation expires
    struct Reservation {
        address owner;
        uint40 expiresAt;
    }

    /// @notice Mapping storing the reservations for each label
    mapping(bytes32 labelHash => Reservation) public reservations;

    /// @notice Emitted when a Werk space successfully claims a subname
    /// @param space The Werk space address
    /// @param label The plaintext label (e.g. "alice")
    /// @param tokenId The tokenId of the subname in `WERK_REGISTRY`
    /// @param node The ENS node hash for `label.werk.eth`
    event WerkSubnameClaimed(address indexed space, string label, uint256 indexed tokenId, bytes32 node);

    /// @notice Emitted when a subdomain is reserved
    /// @param label The reserved label (e.g. "alice" in "alice.werk.eth")
    /// @param owner The owner of the reserved subdomain
    /// @param expiresAt The timestamp at which the reservation expires
    event SubnameReserved(string indexed label, address indexed owner, uint40 expiresAt);

    /// @notice Revert when `space` is the zero address
    error ZeroSpace();

    /// @notice Revert when caller is not the Werk space address
    error NotSpaceCaller();

    /// @notice Revert when `label` is empty
    error EmptyLabel();

    /// @notice Revert when the space already has a subname registered
    /// @param space The Werk space address
    /// @param existingLabelHash Previously stored label hash
    error SpaceAlreadyHasSubname(address space, bytes32 existingLabelHash);

    /// @notice Revert when the label is already taken by another space
    /// @param labelHash Label hash that is already taken
    /// @param existingSpace Werk space that already claimed the label
    error LabelAlreadyTaken(bytes32 labelHash, address existingSpace);

    /// @notice Revert when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Revert when the caller does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Revert when the subdomain has already been reserved
    error AlreadyReserved(uint40 expiresAt);

    /// @notice Revert when the reservation has expired
    error ReservationExpired();

    /// @notice Revert when there is no reservation found for the given label
    error ReservationNotFound();

    /// @notice Revert when the caller is not the owner of the reservation
    error NotReservationOwner(uint40 expiresAt);

    /// @param werkRegistry ENSv2 registry that holds all `werk.eth` subnames
    /// @param resolver Shared resolver used for all werk subnames
    /// @param werkNode Namehash of `werk.eth`
    /// @param owner Address of the registrar owner
    constructor(IPermissionedRegistry werkRegistry, address resolver, bytes32 werkNode, address owner) Ownable(owner) {
        if (address(werkRegistry) == address(0)) {
            revert ZeroSpace();
        }
        if (resolver == address(0)) {
            revert ZeroSpace();
        }

        WERK_REGISTRY = werkRegistry;
        RESOLVER = resolver;
        WERK_NODE = werkNode;
    }

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        _onlySpace();
        _;
    }

    /// @notice Checks if a given label is available for registration
    /// @param label The label to check availability for
    /// @return True if the label can be registered, false if already taken or actively reserved
    function available(string calldata label) external view returns (bool) {
        bytes32 labelHash = keccak256(bytes(label));

        // Check if the label is already claimed
        if (labelToSpace[labelHash] != address(0)) {
            return false;
        }

        // Check if there is an active reservation for the label
        Reservation memory reservation = reservations[labelHash];
        if (reservation.owner != address(0) && reservation.expiresAt > block.timestamp) {
            return false;
        }

        return true;
    }

    /// @notice Reserves a label for 30 minutes for the caller
    /// @param label The label to reserve (e.g. "alice" for "alice.werk.eth")
    function reserve(string calldata label) external {
        bytes memory labelBytes = bytes(label);
        if (labelBytes.length == 0) revert EmptyLabel();

        bytes32 labelHash = keccak256(labelBytes);

        // Check if the label is already claimed.
        address existingSpace = labelToSpace[labelHash];
        if (existingSpace != address(0)) {
            revert LabelAlreadyTaken(labelHash, existingSpace);
        }

        // Check if there is an existing reservation that is still valid (not expired).
        Reservation memory reservation = reservations[labelHash];
        if (reservation.owner != address(0) && reservation.expiresAt > block.timestamp) {
            revert AlreadyReserved({ expiresAt: reservation.expiresAt });
        }

        uint40 expiresAt = uint40(block.timestamp + 30 minutes);
        reservations[labelHash] = Reservation({ owner: msg.sender, expiresAt: expiresAt });

        emit SubnameReserved({ label: label, owner: msg.sender, expiresAt: expiresAt });
    }

    /// @notice Claim a subname `<label>.werk.eth` for a Werk space
    /// @dev Enforces:
    ///  - `msg.sender` must be a contract implementing {ISpace}
    ///  - `msg.sender` must have a valid reservation for the label
    ///  - one subname per space
    ///  - unique labels under `werk.eth`
    /// Requires this contract to have `ROLE_REGISTRAR` on `werkRegistry`
    /// @param label subname for "werk.eth", e.g. "alice" for `alice.werk.eth`
    function claimSubname(string calldata label) external onlySpace nonReentrant {
        bytes memory labelBytes = bytes(label);
        if (labelBytes.length == 0) revert EmptyLabel();

        bytes32 labelHash = keccak256(labelBytes);

        // Validate reservation.
        _validateReservation(labelHash, msg.sender);

        // One subname per space.
        bytes32 existingLabelForSpace = spaceToLabel[msg.sender];
        if (existingLabelForSpace != bytes32(0)) {
            revert SpaceAlreadyHasSubname(msg.sender, existingLabelForSpace);
        }

        // Unique label across spaces.
        address existingSpace = labelToSpace[labelHash];
        if (existingSpace != address(0)) {
            revert LabelAlreadyTaken(labelHash, existingSpace);
        }

        // Clear the reservation and mark mappings
        delete reservations[labelHash];
        spaceToLabel[msg.sender] = labelHash;
        labelToSpace[labelHash] = msg.sender;

        // Register the name in the Werk registry and set the default address record.
        uint256 tokenId = _registerAndSetAddr(label, labelHash, msg.sender);

        emit WerkSubnameClaimed(msg.sender, label, tokenId, keccak256(abi.encodePacked(WERK_NODE, labelHash)));
    }

    /// @notice Add or update an address record for an additional coin type for an existing Werk subname
    /// @dev Uses the caller's address as the encoded value, consistent with `claimSubname`
    ///      Caller must be the Werk space that owns the subname
    /// @param label Leftmost label, e.g. "alice" for `alice.werk.eth`
    /// @param coinType ENSIP-11 coin type to set an address for
    function addCoinType(string calldata label, uint256 coinType) external onlySpace nonReentrant {
        if (coinType == 0) {
            revert ZeroSpace();
        }

        bytes memory labelBytes = bytes(label);
        if (labelBytes.length == 0) revert EmptyLabel();

        bytes32 labelHash = keccak256(labelBytes);

        // Only the space that owns this label may extend its records.
        address space = labelToSpace[labelHash];
        if (space == address(0) || space != msg.sender) {
            revert NotSpaceCaller();
        }

        bytes32 node = keccak256(abi.encodePacked(WERK_NODE, labelHash));
        bytes memory addrBytes = abi.encodePacked(space);

        IAddrResolver(RESOLVER).setAddr(node, coinType, addrBytes);
    }

    /// @notice Return the Werk space that claimed a given label
    /// @param label Leftmost label, e.g. "alice"
    /// @return space Werk space address that claimed the label (zero if none)
    function getSpaceForLabel(string calldata label) external view returns (address space) {
        bytes32 labelHash = keccak256(bytes(label));
        return labelToSpace[labelHash];
    }

    /// @notice Return the label hash claimed by a given Werk space
    /// @param space Werk space address
    /// @return labelHash Label hash claimed by the space (zero if none)
    function getLabelHashForSpace(address space) external view returns (bytes32 labelHash) {
        return spaceToLabel[space];
    }

    /// @notice Withdraws an ERC-20 token from the Registrar
    /// @param asset The ERC-20 token to withdraw
    /// @param amount The amount of tokens to withdraw
    function withdrawERC20(IERC20 asset, uint256 amount) public onlyOwner {
        asset.safeTransfer(owner, amount);
    }

    /// @notice Withdraws native tokens (ETH) from the Registrar
    /// @param amount The amount of native tokens to withdraw
    function withdrawNative(uint256 amount) public onlyOwner {
        (bool success,) = owner.call{ value: amount }("");
        if (!success) revert();
    }

    /// @dev Validates that `space` has an active reservation for `labelHash`
    function _validateReservation(bytes32 labelHash, address space) internal view {
        Reservation memory reservation = reservations[labelHash];
        if (reservation.owner == address(0)) {
            revert ReservationNotFound();
        }
        if (reservation.expiresAt < block.timestamp) {
            revert ReservationExpired();
        }
        if (reservation.owner != space) {
            revert NotReservationOwner({ expiresAt: reservation.expiresAt });
        }
    }

    /// @dev Registers the subname on the Werk registry and sets the ENSIP-19 default address record
    function _registerAndSetAddr(
        string calldata label,
        bytes32 labelHash,
        address space
    )
        internal
        returns (uint256 tokenId)
    {
        // Note: ROLE_CAN_TRANSFER_ADMIN is intentionally omitted to prevent transfers
        // from desyncing the registrar's `spaceToLabel` and `labelToSpace` mappings
        uint256 rolesForSpace =
            RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_UNREGISTER;

        tokenId = IStandardRegistry(address(WERK_REGISTRY))
            .register(label, space, IRegistry(address(0)), RESOLVER, rolesForSpace, type(uint64).max);

        bytes32 node = keccak256(abi.encodePacked(WERK_NODE, labelHash));
        IAddrResolver(RESOLVER).setAddr(node, COIN_TYPE_DEFAULT, abi.encodePacked(space));
    }

    /// @dev Checks that `msg.sender` is a deployed contract implementing {ISpace}
    function _onlySpace() internal view {
        if (msg.sender.code.length == 0) {
            revert SpaceZeroCodeSize();
        }

        bytes4 interfaceId = type(ISpace).interfaceId;
        if (!ISpace(msg.sender).supportsInterface(interfaceId)) revert SpaceUnsupportedInterface();
    }
}
