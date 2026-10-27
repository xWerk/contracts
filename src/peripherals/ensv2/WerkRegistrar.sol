// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { ENSIP19 } from "@ens/contracts/utils/ENSIP19.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { Ownable } from "./../../abstracts/Ownable.sol";

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
    /// @dev See https://docs.ens.domains/resolution/names/
    bytes32 public constant WERK_NODE = 0x628ee8eef5c1212354266f4458b77fa81c351f6d80eef1cdd59827763d44edb8;

    /// @notice DNS-encoded `werk.eth` suffix, appended to a length-prefixed label to build a full DNS-encoded name
    /// @dev The ENSv2 resolver keys records by DNS-encoded name rather than by node
    bytes public constant WERK_DNS_SUFFIX = hex"047765726b0365746800";

    /// @notice Minimum length of a label
    uint256 public constant MIN_LABEL_LENGTH = 3;

    /// @notice Maximum length of a label, matching the DNS limit for a single label
    uint256 public constant MAX_LABEL_LENGTH = 63;

    /// @notice Maps a Werk space to its claimed label hash
    // Note: helps to enforce one subname per space
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

    /// @notice Revert when `coinType` is not an EVM coin type, as a space's address is only valid on EVM chains
    /// @param coinType The rejected ENSIP-11 coin type
    error InvalidCoinType(uint256 coinType);

    /// @notice Revert when caller is not the Werk space address
    error NotSpaceCaller();

    /// @notice Revert when `label` does not follow the label rules enforced by {_isValidLabel}
    /// @param label The rejected label
    error InvalidLabel(string label);

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
    /// @param owner Address of the registrar owner
    constructor(IPermissionedRegistry werkRegistry, address resolver, address owner) Ownable(owner) {
        WERK_REGISTRY = werkRegistry;
        RESOLVER = resolver;
    }

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        _onlySpace();
        _;
    }

    /// @notice Checks if a given label is available for registration
    /// @param label The label to check availability for
    /// @return True if the label can be registered, false if invalid, already taken or actively reserved
    function available(string calldata label) external view returns (bool) {
        // Check if the label follows the label rules
        if (!_isValidLabel(label)) {
            return false;
        }

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
    function reserve(string calldata label) external onlySpace {
        if (!_isValidLabel(label)) revert InvalidLabel(label);

        bytes32 labelHash = keccak256(bytes(label));

        // Check if the label is already claimed
        address existingSpace = labelToSpace[labelHash];
        if (existingSpace != address(0)) {
            revert LabelAlreadyTaken(labelHash, existingSpace);
        }

        // Check if there is an existing reservation that is still valid (not expired)
        Reservation memory reservation = reservations[labelHash];
        if (reservation.owner != address(0) && reservation.expiresAt > block.timestamp) {
            revert AlreadyReserved({ expiresAt: reservation.expiresAt });
        }

        uint40 expiresAt = uint40(block.timestamp + 30 minutes);
        reservations[labelHash] = Reservation({ owner: msg.sender, expiresAt: expiresAt });

        emit SubnameReserved({ label: label, owner: msg.sender, expiresAt: expiresAt });
    }

    /// @notice Claim a subname `<label>.werk.eth` for a Werk space
    /// @dev Requirements:
    ///  - `msg.sender` must be a contract implementing {ISpace}
    ///  - `msg.sender` must have a valid reservation for the label
    ///  - one subname per space
    ///  - unique labels under `werk.eth`
    /// Requires this contract to have `ROLE_REGISTRAR` on `werkRegistry`
    /// @param label subname for "werk.eth", e.g. "alice" for `alice.werk.eth`
    function register(string calldata label) external onlySpace nonReentrant {
        if (!_isValidLabel(label)) revert InvalidLabel(label);

        bytes32 labelHash = keccak256(bytes(label));

        // Validate reservation
        _validateReservation(labelHash, msg.sender);

        // One subname per space
        bytes32 existingLabelForSpace = spaceToLabel[msg.sender];
        if (existingLabelForSpace != bytes32(0)) {
            revert SpaceAlreadyHasSubname(msg.sender, existingLabelForSpace);
        }

        // Unique label across spaces
        address existingSpace = labelToSpace[labelHash];
        if (existingSpace != address(0)) {
            revert LabelAlreadyTaken(labelHash, existingSpace);
        }

        // Clear the reservation and mark mappings
        delete reservations[labelHash];
        spaceToLabel[msg.sender] = labelHash;
        labelToSpace[labelHash] = msg.sender;

        // Register the name in the Werk registry and set the default address record
        uint256 tokenId = _registerAndSetAddr(label, msg.sender);

        emit WerkSubnameClaimed(msg.sender, label, tokenId, keccak256(abi.encodePacked(WERK_NODE, labelHash)));
    }

    /// @notice Add or update an address record for an additional coin type for an existing Werk subname
    /// @dev Uses the caller's address as the encoded value, consistent with `register`
    ///      Caller must be the Werk space that owns the subname
    ///      Only EVM coin types are accepted as the space's address is meaningless on non-EVM chains
    /// @param label Leftmost label, e.g. "alice" for `alice.werk.eth`
    /// @param coinType ENSIP-11 coin type to set an address for
    function addCoinType(string calldata label, uint256 coinType) external onlySpace nonReentrant {
        if (!ENSIP19.isEVMCoinType(coinType)) {
            revert InvalidCoinType(coinType);
        }

        // Only the space that owns this label may extend its records
        // Note: no label validation needed as only valid labels can be registered
        address space = labelToSpace[keccak256(bytes(label))];
        if (space == address(0) || space != msg.sender) {
            revert NotSpaceCaller();
        }

        IAddressSetter(RESOLVER).setAddress(_dnsEncode(label), coinType, abi.encodePacked(space));
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
        if (reservation.expiresAt <= block.timestamp) {
            revert ReservationExpired();
        }
        if (reservation.owner != space) {
            revert NotReservationOwner({ expiresAt: reservation.expiresAt });
        }
    }

    /// @dev Registers the subname on the Werk registry and sets the ENSIP-19 default address record
    function _registerAndSetAddr(string calldata label, address space) internal returns (uint256 tokenId) {
        // Note: the space is granted no roles on its subname. `ROLE_CAN_TRANSFER_ADMIN`, `ROLE_UNREGISTER` and
        // `ROLE_SET_RESOLVER` would let it transfer, unregister or repoint the subname and desync the registrar's
        // `spaceToLabel` and `labelToSpace` mappings, while `ROLE_RENEW` is useless as the subname never expires
        tokenId = WERK_REGISTRY.register(label, space, IRegistry(address(0)), RESOLVER, 0, type(uint64).max);

        IAddressSetter(RESOLVER).setAddress(_dnsEncode(label), COIN_TYPE_DEFAULT, abi.encodePacked(space));
    }

    /// @dev Checks that `label` follows the label rules, which guarantee it is already ENSIP-15 normalized:
    ///  - between `MIN_LABEL_LENGTH` and `MAX_LABEL_LENGTH` characters
    ///  - only lowercase letters (a-z), digits (0-9) and hyphens (-)
    ///  - no leading or trailing hyphen
    ///  - no hyphens at both the 3rd and 4th positions (reserved for the "xn--" punycode prefix)
    function _isValidLabel(string calldata label) internal pure returns (bool) {
        bytes calldata labelBytes = bytes(label);
        uint256 length = labelBytes.length;

        // Checks: the label length is within bounds
        if (length < MIN_LABEL_LENGTH || length > MAX_LABEL_LENGTH) return false;

        // Checks: the label does not start or end with a hyphen
        if (labelBytes[0] == "-" || labelBytes[length - 1] == "-") return false;

        // Checks: the label does not have hyphens at both the 3rd and 4th positions
        if (length > 3 && labelBytes[2] == "-" && labelBytes[3] == "-") return false;

        // Checks: every character is a lowercase letter, a digit or a hyphen
        for (uint256 i; i < length; ++i) {
            bytes1 char = labelBytes[i];
            bool isLetter = char >= "a" && char <= "z";
            bool isDigit = char >= "0" && char <= "9";
            if (!isLetter && !isDigit && char != "-") return false;
        }

        return true;
    }

    /// @dev Builds the DNS-encoded name `<label>.werk.eth`
    /// Note: `label` is at most `MAX_LABEL_LENGTH` bytes long and contains no dot as only valid labels are registered
    function _dnsEncode(string calldata label) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(label).length), label, WERK_DNS_SUFFIX);
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
