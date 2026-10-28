// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { COIN_TYPE_DEFAULT } from "@ens/contracts/utils/ENSIP19.sol";
import { NameCoder } from "@ens/contracts/utils/NameCoder.sol";
import { ISpace } from "./../../interfaces/ISpace.sol";
import { ISpaceFactory } from "./interfaces/ISpaceFactory.sol";

/// @title WerkRegistrar
/// @notice Registrar for subnames under `werk.eth`, enforcing one active subname per Werk space
/// @dev The Werk registry is the source of truth for label ownership and expiry. A subname is held for
/// `REGISTRATION_PERIOD` followed by a `GRACE_PERIOD` during which only the owning space can renew it
contract WerkRegistrar is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "1.0.0";

    /// @dev Period a subname is held for before its grace period starts
    uint256 internal constant REGISTRATION_PERIOD = 365 days;

    /// @dev Period after `REGISTRATION_PERIOD` during which only the owning space can renew its subname
    /// Note: the subname keeps resolving during the grace period
    uint256 internal constant GRACE_PERIOD = 30 days;

    /// @dev Period a label is reserved for, also used as the cooldown before the same space can reserve it again
    uint256 internal constant RESERVATION_PERIOD = 30 minutes;

    /// @dev Namehash of `werk.eth`, used as parent node for subname nodes
    /// See https://docs.ens.domains/resolution/names/
    bytes32 internal constant WERK_NODE = 0x628ee8eef5c1212354266f4458b77fa81c351f6d80eef1cdd59827763d44edb8;

    /// @dev DNS-encoded `werk.eth` suffix, appended to a length-prefixed label to build a full DNS-encoded name
    /// The ENSv2 resolver keys records by DNS-encoded name rather than by node
    bytes internal constant WERK_DNS_SUFFIX = hex"047765726b0365746800";

    /// @dev Minimum length of a label
    uint256 internal constant MIN_LABEL_LENGTH = 3;

    /// @dev Maximum length of a label, matching the DNS limit for a single label
    uint256 internal constant MAX_LABEL_LENGTH = 63;

    /// @notice Reservation details for a label
    /// @param owner The address that owns the reservation
    /// @param expiresAt The timestamp at which the reservation expires
    struct Reservation {
        address owner;
        uint40 expiresAt;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.WerkRegistrar
    struct WerkRegistrarStorage {
        /// @notice ENSv2 registry that holds all subnames under `werk.eth`
        IPermissionedRegistry werkRegistry;
        /// @notice Shared resolver used for all werk subnames
        address resolver;
        /// @notice Factory that deploys and registers Werk spaces
        ISpaceFactory stationRegistry;
        /// @notice Maps a Werk space to the label hash it last claimed
        /// @dev Only a pointer into the registry: the claim is active only while the registry reports the label as
        /// registered to that space
        mapping(address space => bytes32 labelHash) spaceToLabel;
        /// @notice Reservations mapped by label hash
        mapping(bytes32 labelHash => Reservation) reservations;
        /// @notice Maps a Werk space to the label hash of its latest reservation
        /// @dev Used to enforce one active reservation per space
        mapping(address space => bytes32 labelHash) reservationOf;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.WerkRegistrar")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WERK_REGISTRAR_STORAGE_LOCATION =
        0x74b174fbb953ed4f640f28a2f0263e077eb5f3c9ea0e9b695b9d4c9ee5de6200;

    /// @dev Retrieves the storage of the {WerkRegistrar} contract
    function _getWerkRegistrarStorage() internal pure returns (WerkRegistrarStorage storage $) {
        assembly {
            $.slot := WERK_REGISTRAR_STORAGE_LOCATION
        }
    }

    /// @notice Emitted when a Werk space successfully claims a subname
    /// @param space The Werk space address
    /// @param label The plaintext label (e.g. "alice")
    /// @param tokenId The tokenId of the subname in `WERK_REGISTRY`
    /// @param node The ENS node hash for `label.werk.eth`
    /// @param expiry The timestamp at which the subname expires, including the grace period
    event WerkSubnameClaimed(address indexed space, string label, uint256 indexed tokenId, bytes32 node, uint64 expiry);

    /// @notice Emitted when a Werk space renews its subname
    /// @param space The Werk space address
    /// @param label The plaintext label (e.g. "alice")
    /// @param expiry The new timestamp at which the subname expires, including the grace period
    event SubnameRenewed(address indexed space, string label, uint64 expiry);

    /// @notice Emitted when the owner clears a subname
    /// @param space The Werk space that held the subname
    /// @param label The plaintext label (e.g. "alice")
    event LabelCleared(address indexed space, string label);

    /// @notice Emitted when a subdomain is reserved
    /// @param label The reserved label (e.g. "alice" in "alice.werk.eth")
    /// @param owner The owner of the reserved subdomain
    /// @param expiresAt The timestamp at which the reservation expires
    event SubnameReserved(string indexed label, address indexed owner, uint40 expiresAt);

    /// @notice Revert when the caller does not own the subname
    /// @param caller The caller that is not the owner of the subname
    error NotSubnameOwner(address caller);

    /// @notice Revert when the subname cannot be renewed yet as its grace period has not started
    /// @param opensAt The timestamp at which the grace period starts
    error RenewalNotOpen(uint64 opensAt);

    /// @notice Revert when `label` does not follow the label rules enforced by {_isValidLabel}
    /// @param label The rejected label
    error InvalidLabel(string label);

    /// @notice Revert when the space already has an active subname
    /// @param space The Werk space address
    /// @param existingLabelHash Label hash of the active subname
    error SpaceAlreadyHasSubname(address space, bytes32 existingLabelHash);

    /// @notice Revert when the label is already taken by another space
    /// @param labelHash Label hash that is already taken
    /// @param existingSpace Werk space that already claimed the label
    error LabelAlreadyTaken(bytes32 labelHash, address existingSpace);

    /// @notice Revert when the caller is an invalid zero code contract or EOA
    error SpaceZeroCodeSize();

    /// @notice Revert when the caller does not implement the {ISpace} interface
    error SpaceUnsupportedInterface();

    /// @notice Revert when the caller is not a Space registered on the `STATION_REGISTRY`
    error SpaceNotRegistered();

    /// @notice Revert when the subdomain has already been reserved
    error AlreadyReserved(uint40 expiresAt);

    /// @notice Revert when the caller reserves again a label it held until the end of its cooldown
    /// @param endsAt The timestamp at which the caller can reserve the label again
    error ReservationCooldown(uint256 endsAt);

    /// @notice Revert when the reservation has expired
    error ReservationExpired();

    /// @notice Revert when there is no reservation found for the given label
    error ReservationNotFound();

    /// @notice Revert when the caller is not the owner of the reservation
    error NotReservationOwner(uint40 expiresAt);

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys and locks the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the proxy and the {Ownable} contract
    /// @param werkRegistry ENSv2 registry that holds all `werk.eth` subnames
    /// @param resolver Shared resolver used for all werk subnames
    /// @param stationRegistry Factory that deploys and registers Werk spaces
    /// @param initialAdmin Address of the registrar owner
    function initialize(
        IPermissionedRegistry werkRegistry,
        address resolver,
        ISpaceFactory stationRegistry,
        address initialAdmin
    )
        public
        initializer
    {
        __Ownable_init(initialAdmin);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        $.werkRegistry = werkRegistry;
        $.resolver = resolver;
        $.stationRegistry = stationRegistry;
    }

    /// @dev Allows only the owner to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice ENSv2 registry that holds all subnames under `werk.eth`
    function WERK_REGISTRY() public view returns (IPermissionedRegistry) {
        return _getWerkRegistrarStorage().werkRegistry;
    }

    /// @notice Shared resolver used for all werk subnames
    function RESOLVER() public view returns (address) {
        return _getWerkRegistrarStorage().resolver;
    }

    /// @notice Factory that deploys and registers Werk spaces
    function STATION_REGISTRY() public view returns (ISpaceFactory) {
        return _getWerkRegistrarStorage().stationRegistry;
    }

    /// @notice Returns the reservation of a label
    /// @param labelHash The label hash of the reservation
    /// @return owner The address that owns the reservation
    /// @return expiresAt The timestamp at which the reservation expires
    function reservations(bytes32 labelHash) external view returns (address owner, uint40 expiresAt) {
        Reservation memory reservation = _getWerkRegistrarStorage().reservations[labelHash];
        return (reservation.owner, reservation.expiresAt);
    }

    /// @notice Returns the label hash of the latest reservation of a Werk space
    /// @param space The Werk space address
    function reservationOf(address space) external view returns (bytes32 labelHash) {
        return _getWerkRegistrarStorage().reservationOf[space];
    }

    /// @dev Allow only calls from Werk spaces registered on the `STATION_REGISTRY`
    modifier onlySpace() {
        _onlySpace();
        _;
    }

    /// @notice Checks if a given label is available for registration
    /// @param label The label to check availability for
    /// @return True if the label can be registered, false if invalid, taken (incl. grace period) or actively reserved
    function available(string calldata label) external view returns (bool) {
        // Check if the label follows the label rules
        if (!_isValidLabel(label)) {
            return false;
        }

        bytes32 labelHash = keccak256(bytes(label));

        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        // Check if the label is registered on the Werk registry, including during its grace period
        if ($.werkRegistry.getStatus(uint256(labelHash)) != IPermissionedRegistry.Status.AVAILABLE) {
            return false;
        }

        // Check if there is an active reservation for the label
        return $.reservations[labelHash].expiresAt <= block.timestamp;
    }

    /// @notice Reserves a label for `RESERVATION_PERIOD` for the caller
    /// @dev Requirements:
    ///  - the caller has no active subname
    ///  - the label is not registered nor actively reserved
    ///  - the caller did not hold a reservation for the label during the last `RESERVATION_PERIOD`
    /// Reserving a new label releases the caller's previous active reservation, keeping one per space
    /// @param label The label to reserve (e.g. "alice" for "alice.werk.eth")
    function reserve(string calldata label) external onlySpace {
        if (!_isValidLabel(label)) revert InvalidLabel(label);

        // Checks: the caller has no active subname as it could not register a second one
        bytes32 activeLabelHash = _activeLabelHash(msg.sender);
        if (activeLabelHash != bytes32(0)) revert SpaceAlreadyHasSubname(msg.sender, activeLabelHash);

        bytes32 labelHash = keccak256(bytes(label));

        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        // Checks: the label is not registered, including during its grace period
        IPermissionedRegistry.State memory state = $.werkRegistry.getState(uint256(labelHash));
        if (state.status != IPermissionedRegistry.Status.AVAILABLE) {
            revert LabelAlreadyTaken(labelHash, state.latestOwner);
        }

        // Checks: there is no reservation for the label that is still valid (not expired)
        // Note: an empty reservation has a zero `expiresAt`, so it never counts as valid
        Reservation memory reservation = $.reservations[labelHash];
        if (reservation.expiresAt > block.timestamp) {
            revert AlreadyReserved({ expiresAt: reservation.expiresAt });
        }

        // Checks: the caller did not just hold the label, so that it cannot keep it reserved indefinitely
        if (reservation.owner == msg.sender && block.timestamp < reservation.expiresAt + RESERVATION_PERIOD) {
            revert ReservationCooldown({ endsAt: reservation.expiresAt + RESERVATION_PERIOD });
        }

        // Effects: release the caller's previous active reservation by expiring it now
        // Note: the released reservation keeps its owner so that the cooldown also applies to it
        bytes32 previousLabelHash = $.reservationOf[msg.sender];
        Reservation storage previous = $.reservations[previousLabelHash];
        if (previous.owner == msg.sender && previous.expiresAt > block.timestamp) {
            previous.expiresAt = uint40(block.timestamp);
        }

        // Effects: reserve the label for the caller
        uint40 expiresAt = uint40(block.timestamp + RESERVATION_PERIOD);
        $.reservations[labelHash] = Reservation({ owner: msg.sender, expiresAt: expiresAt });
        $.reservationOf[msg.sender] = labelHash;

        emit SubnameReserved({ label: label, owner: msg.sender, expiresAt: expiresAt });
    }

    /// @notice Claim a subname `<label>.werk.eth` for a Werk space for `REGISTRATION_PERIOD` + `GRACE_PERIOD`
    /// @dev Requirements:
    ///  - `msg.sender` must be a Werk space registered on the `STATION_REGISTRY`
    ///  - `msg.sender` must have a valid reservation for the label
    ///  - one active subname per space
    /// Requires this contract to have `ROLE_REGISTRAR` on `werkRegistry`
    /// @param label subname for "werk.eth", e.g. "alice" for `alice.werk.eth`
    function register(string calldata label) external onlySpace nonReentrant {
        if (!_isValidLabel(label)) revert InvalidLabel(label);

        bytes32 labelHash = keccak256(bytes(label));

        // Validate reservation
        // Note: a valid reservation implies the label was available when reserved and nobody else could register it.
        // It also enforces one active subname per space without re-checking it here: {reserve} rejects spaces holding
        // an active subname, and a space holds at most one valid reservation that this call consumes
        _validateReservation(labelHash, msg.sender);

        // Clear the reservation and point the space to its new label
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();
        delete $.reservations[labelHash];
        delete $.reservationOf[msg.sender];
        $.spaceToLabel[msg.sender] = labelHash;

        // Register the name in the Werk registry and set the default address record
        uint64 expiry = uint64(block.timestamp + REGISTRATION_PERIOD + GRACE_PERIOD);
        uint256 tokenId = _registerAndSetAddr(label, msg.sender, expiry);

        emit WerkSubnameClaimed(msg.sender, label, tokenId, NameCoder.namehash(WERK_NODE, labelHash), expiry);
    }

    /// @notice Renews the caller's subname for another `REGISTRATION_PERIOD`
    /// @dev Only allowed during the grace period, i.e. after `REGISTRATION_PERIOD` and before the subname expires
    /// Requires this contract to have `ROLE_RENEW` on `werkRegistry`
    /// @param label Leftmost label, e.g. "alice" for `alice.werk.eth`
    function renew(string calldata label) external onlySpace {
        uint256 labelId = uint256(keccak256(bytes(label)));
        IPermissionedRegistry werkRegistry = _getWerkRegistrarStorage().werkRegistry;
        IPermissionedRegistry.State memory state = werkRegistry.getState(labelId);

        // Checks: the caller owns the subname, which also implies it has not expired
        if (state.status != IPermissionedRegistry.Status.REGISTERED || state.latestOwner != msg.sender) {
            revert NotSubnameOwner(msg.sender);
        }

        // Checks: the grace period has started
        uint64 graceStart = state.expiry - uint64(GRACE_PERIOD);
        if (block.timestamp < graceStart) revert RenewalNotOpen(graceStart);

        // Interactions: extend the subname by another registration period
        uint64 newExpiry = state.expiry + uint64(REGISTRATION_PERIOD);
        werkRegistry.renew(labelId, newExpiry);

        emit SubnameRenewed(msg.sender, label, newExpiry);
    }

    /// @notice Clears multiple subnames
    /// @dev Unregisters each subname and resets its default address record. Labels that are not registered
    /// (unclaimed or expired) are skipped. Requires this contract to have `ROLE_UNREGISTER` on `werkRegistry`
    /// @param labels Leftmost labels to clear, e.g. "alice" for `alice.werk.eth`
    function clearLabels(string[] calldata labels) external onlyOwner {
        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        for (uint256 i; i < labels.length; ++i) {
            bytes32 labelHash = keccak256(bytes(labels[i]));

            // Skip labels that are not registered
            address space = _registeredOwner(labelHash);
            if (space == address(0)) continue;

            // Effects: drop the space's pointer to the label
            if ($.spaceToLabel[space] == labelHash) delete $.spaceToLabel[space];

            // Interactions: unregister the subname and reset its default address record so that a future
            // registration of the label never resolves to this space
            $.werkRegistry.unregister(uint256(labelHash));
            IAddressSetter($.resolver).setAddress(_dnsEncode(labels[i]), COIN_TYPE_DEFAULT, "");

            emit LabelCleared(space, labels[i]);
        }
    }

    /// @notice Return the Werk space that holds a given label
    /// @param label Leftmost label, e.g. "alice"
    /// @return space Werk space address that holds the label (zero if none or expired)
    function getSpaceForLabel(string calldata label) external view returns (address space) {
        return _registeredOwner(keccak256(bytes(label)));
    }

    /// @notice Return the label hash of the active subname held by a given Werk space
    /// @param space Werk space address
    /// @return labelHash Label hash of the active subname (zero if none or expired)
    function getLabelHashForSpace(address space) external view returns (bytes32 labelHash) {
        return _activeLabelHash(space);
    }

    /// @dev Validates that `space` has an active reservation for `labelHash`
    function _validateReservation(bytes32 labelHash, address space) internal view {
        Reservation memory reservation = _getWerkRegistrarStorage().reservations[labelHash];
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

    /// @dev Returns the label hash of the active subname held by `space`, or zero if it holds none
    /// The subname is active only while its last claimed label is still registered to it on the Werk registry
    function _activeLabelHash(address space) internal view returns (bytes32 labelHash) {
        labelHash = _getWerkRegistrarStorage().spaceToLabel[space];
        if (labelHash != bytes32(0) && _registeredOwner(labelHash) != space) return bytes32(0);
    }

    /// @dev Returns the space holding `labelHash` on the Werk registry, or zero if the label is not registered
    /// Note: an expired or unregistered label is reported as not registered by the registry
    function _registeredOwner(bytes32 labelHash) internal view returns (address) {
        IPermissionedRegistry.State memory state = _getWerkRegistrarStorage().werkRegistry.getState(uint256(labelHash));
        return state.status == IPermissionedRegistry.Status.REGISTERED ? state.latestOwner : address(0);
    }

    /// @dev Registers the subname on the Werk registry until `expiry` and sets the ENSIP-19 default address record
    function _registerAndSetAddr(
        string calldata label,
        address space,
        uint64 expiry
    )
        internal
        returns (uint256 tokenId)
    {
        // Note: the space is granted no roles on its subname. `ROLE_CAN_TRANSFER_ADMIN`, `ROLE_UNREGISTER`,
        // `ROLE_SET_RESOLVER` and `ROLE_RENEW` would let it transfer, unregister, repoint or renew the subname
        // outside of the registrar rules
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();
        address resolver = $.resolver;
        tokenId = $.werkRegistry.register(label, space, IRegistry(address(0)), resolver, 0, expiry);

        // Note: overwrites the record of any previous owner of the label
        IAddressSetter(resolver).setAddress(_dnsEncode(label), COIN_TYPE_DEFAULT, abi.encodePacked(space));
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
        // Note: a 3-character label never reads index 3, as a hyphen at index 2 was rejected as trailing above
        if (labelBytes[2] == "-" && labelBytes[3] == "-") return false;

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
    function _dnsEncode(string calldata label) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(label).length), label, WERK_DNS_SUFFIX);
    }

    /// @dev Checks that `msg.sender` is a deployed contract implementing {ISpace} and registered as a Werk space
    function _onlySpace() internal view {
        if (msg.sender.code.length == 0) {
            revert SpaceZeroCodeSize();
        }

        if (!ISpace(msg.sender).supportsInterface(type(ISpace).interfaceId)) revert SpaceUnsupportedInterface();

        if (!_getWerkRegistrarStorage().stationRegistry.isRegistered(msg.sender)) revert SpaceNotRegistered();
    }
}
