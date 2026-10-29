// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { COIN_TYPE_DEFAULT } from "@ens/contracts/utils/ENSIP19.sol";
import { NameCoder } from "@ens/contracts/utils/NameCoder.sol";

/// @title WerkRegistrar
/// @notice Registrar for subnames under `werk.eth`, enforcing one active subname per Werk space
/// @dev The Werk registry is the source of truth for label ownership and expiry. A subname is held for
/// `REGISTRATION_PERIOD` followed by a `GRACE_PERIOD` during which only the owning space can renew it
/// Eligibility is decided off-chain: every {register} and {renew} call must carry a signature of the trusted
/// signer over the space, the label and a `validUntil` deadline. The signature is bound to `msg.sender`, and the
/// backend only signs for Space addresses it derives from the `StationRegistry`, so only that Space can use it
contract WerkRegistrar is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @dev Version identifier for the current implementation of the contract
    string public constant VERSION = "1.0.0";

    /// @dev Period a subname is held for before its grace period starts
    uint256 internal constant REGISTRATION_PERIOD = 365 days;

    /// @dev Period after `REGISTRATION_PERIOD` during which only the owning space can renew its subname
    /// Note: the subname keeps resolving during the grace period
    uint256 internal constant GRACE_PERIOD = 30 days;

    /// @dev Action tags mixed into the signed payload so that a signature authorizes a single action
    /// Note: required if the backend sets different rules for register and renew actions
    bytes32 internal constant REGISTER_ACTION = keccak256("WerkRegistrar.register");
    bytes32 internal constant RENEW_ACTION = keccak256("WerkRegistrar.renew");

    /// @dev Namehash of `werk.eth`, used as parent node for subname nodes
    /// See https://docs.ens.domains/resolution/names/
    bytes32 internal constant WERK_NODE = 0x628ee8eef5c1212354266f4458b77fa81c351f6d80eef1cdd59827763d44edb8;

    /// @dev DNS-encoded `werk.eth` suffix, appended to a length-prefixed label to build a full DNS-encoded name
    /// The ENSv2 resolver keys records by DNS-encoded name rather than by node
    bytes internal constant WERK_DNS_SUFFIX = hex"047765726b0365746800";

    /*//////////////////////////////////////////////////////////////////////////
                            NAMESPACED STORAGE LAYOUT
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.WerkRegistrar
    struct WerkRegistrarStorage {
        /// @notice ENSv2 registry that holds all subnames under `werk.eth`
        IPermissionedRegistry werkRegistry;
        /// @notice Shared resolver used for all werk subnames
        address resolver;
        /// @notice Maps a Werk space to the label hash it last claimed
        /// @dev Only a pointer into the registry: the claim is active only while the registry reports the label as
        /// registered to that space
        mapping(address space => bytes32 labelHash) spaceToLabel;
        /// @notice The trusted backend address whose signature authorizes {register} and {renew}
        address signer;
        /// @notice Whether a signed payload was already consumed
        mapping(bytes32 payloadHash => bool used) usedPayloads;
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

    /// @notice Emitted when the owner updates the trusted signer
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @notice Revert when the caller does not own the subname
    /// @param caller The caller that is not the owner of the subname
    error NotSubnameOwner(address caller);

    /// @notice Revert when the subname cannot be renewed yet as its grace period has not started
    /// @param opensAt The timestamp at which the grace period starts
    error RenewalNotOpen(uint64 opensAt);

    /// @notice Revert when the space already has an active subname
    /// @param space The Werk space address
    /// @param existingLabelHash Label hash of the active subname
    error SpaceAlreadyHasSubname(address space, bytes32 existingLabelHash);

    /// @notice Revert when the label is already taken by another space
    /// @param labelHash Label hash that is already taken
    /// @param existingSpace Werk space that already claimed the label
    error LabelAlreadyTaken(bytes32 labelHash, address existingSpace);

    /// @notice Revert when the signature is used after its `validUntil` deadline
    /// @param validUntil The timestamp until which the signature was valid
    error SignatureExpired(uint40 validUntil);

    /// @notice Revert when the signature was not produced by the trusted signer over the expected payload
    error InvalidSignature();

    /// @notice Revert when the signed payload was already consumed by a previous {register} or {renew}
    error SignatureAlreadyUsed();

    /// @notice Revert when the signer is set to the zero address
    error InvalidZeroAddressSigner();

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
    /// @param initialAdmin Address of the registrar owner
    /// @param initialSigner The trusted backend address whose signature authorizes {register} and {renew}
    function initialize(
        IPermissionedRegistry werkRegistry,
        address resolver,
        address initialAdmin,
        address initialSigner
    )
        public
        initializer
    {
        // Checks: the signer is not the zero address
        if (initialSigner == address(0)) revert InvalidZeroAddressSigner();

        __Ownable_init(initialAdmin);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        $.werkRegistry = werkRegistry;
        $.resolver = resolver;
        $.signer = initialSigner;
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

    /// @notice The trusted backend address whose signature authorizes {register} and {renew}
    function signer() external view returns (address) {
        return _getWerkRegistrarStorage().signer;
    }

    /// @notice Checks if a given label is available for registration
    /// @param label The label to check availability for
    /// @return True if the label is not registered (including during its grace period)
    /// Note: does not apply the label policy, which only the trusted signer enforces
    function available(string calldata label) external view returns (bool) {
        return _getWerkRegistrarStorage().werkRegistry.getStatus(uint256(keccak256(bytes(label))))
            == IPermissionedRegistry.Status.AVAILABLE;
    }

    /// @notice Claim a subname `<label>.werk.eth` for a Werk space for `REGISTRATION_PERIOD` + `GRACE_PERIOD`
    /// @dev Requirements:
    ///  - the trusted signer must have signed (`REGISTER_ACTION`, this contract, `msg.sender`, label hash,
    ///    `validUntil`, chain id) and `validUntil` must not have passed
    ///  - one active subname per space
    ///  - the label must not be registered, including during its grace period
    /// The label policy (allowed characters, normalization, reserved labels) is enforced by the trusted signer, whose
    /// signature binds the label hash. An empty or over-long label is rejected by the registry, as its DNS encoding
    /// prefixes the label with its length in a single byte
    /// Requires this contract to have `ROLE_REGISTRAR` on `werkRegistry`
    /// @param label subname for "werk.eth", e.g. "alice" for `alice.werk.eth`
    /// @param validUntil The timestamp until which the signature can be used
    /// @param signature The trusted signer's EIP-191 signature over the payload
    function register(string calldata label, uint40 validUntil, bytes calldata signature) external nonReentrant {
        bytes32 labelHash = keccak256(bytes(label));

        // Checks: the backend authorized this space to claim this label
        _verifySignature(REGISTER_ACTION, labelHash, validUntil, signature);

        // Checks: the caller has no active subname
        bytes32 activeLabelHash = _activeLabelHash(msg.sender);
        if (activeLabelHash != bytes32(0)) revert SpaceAlreadyHasSubname(msg.sender, activeLabelHash);

        // Checks: the label is not registered, including during its grace period
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();
        IPermissionedRegistry.State memory state = $.werkRegistry.getState(uint256(labelHash));
        if (state.status != IPermissionedRegistry.Status.AVAILABLE) {
            revert LabelAlreadyTaken(labelHash, state.latestOwner);
        }

        // Effects: point the space to its new label
        $.spaceToLabel[msg.sender] = labelHash;

        // Register the name in the Werk registry and set the default address record
        uint64 expiry = uint64(block.timestamp + REGISTRATION_PERIOD + GRACE_PERIOD);
        uint256 tokenId = _registerAndSetAddr(label, msg.sender, expiry);

        emit WerkSubnameClaimed(msg.sender, label, tokenId, NameCoder.namehash(WERK_NODE, labelHash), expiry);
    }

    /// @notice Renews the caller's subname for another `REGISTRATION_PERIOD`
    /// @dev Only allowed during the grace period, i.e. after `REGISTRATION_PERIOD` and before the subname expires
    /// The trusted signer must have signed (`RENEW_ACTION`, this contract, `msg.sender`, label hash, `validUntil`,
    /// chain id) and `validUntil` must not have passed
    /// Requires this contract to have `ROLE_RENEW` on `werkRegistry`
    /// @param label Leftmost label, e.g. "alice" for `alice.werk.eth`
    /// @param validUntil The timestamp until which the signature can be used
    /// @param signature The trusted signer's EIP-191 signature over the payload
    function renew(string calldata label, uint40 validUntil, bytes calldata signature) external {
        bytes32 labelHash = keccak256(bytes(label));

        // Checks: the backend authorized this space to renew this label
        _verifySignature(RENEW_ACTION, labelHash, validUntil, signature);

        uint256 labelId = uint256(labelHash);
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

    /// @notice Rotates the trusted signer
    /// @dev Only callable by the owner
    /// @param newSigner The new signer address
    function setSigner(address newSigner) external onlyOwner {
        // Checks: the new signer is not the zero address
        if (newSigner == address(0)) revert InvalidZeroAddressSigner();

        // Retrieve the contract storage
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();

        // Cache the old signer for the event
        address oldSigner = $.signer;

        // Effects: update the signer address
        $.signer = newSigner;

        emit SignerUpdated(oldSigner, newSigner);
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

    /// @dev Checks that the trusted signer authorized `msg.sender` to perform `action` on `labelHash` on this chain,
    /// then consumes the signed payload so that it cannot be replayed
    function _verifySignature(bytes32 action, bytes32 labelHash, uint40 validUntil, bytes calldata signature) internal {
        // Checks: the signature has not expired
        if (block.timestamp > validUntil) revert SignatureExpired(validUntil);

        // Rebuild the payload the signer signed off-chain
        // Note: `address(this)` and `block.chainid` prevent replays on other contracts and chains
        bytes32 payloadHash =
            keccak256(abi.encode(action, address(this), msg.sender, labelHash, validUntil, block.chainid));

        // Checks: the payload was not consumed yet
        WerkRegistrarStorage storage $ = _getWerkRegistrarStorage();
        if ($.usedPayloads[payloadHash]) revert SignatureAlreadyUsed();

        // Checks: the recovered signer is the trusted signer
        // Note: `tryRecover` is used so that a malformed signature reverts with {InvalidSignature} too
        (address recovered, ECDSA.RecoverError error,) = payloadHash.toEthSignedMessageHash().tryRecover(signature);
        if (error != ECDSA.RecoverError.NoError || recovered != $.signer) {
            revert InvalidSignature();
        }

        // Effects: consume the payload
        $.usedPayloads[payloadHash] = true;
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

    /// @dev Builds the DNS-encoded name `<label>.werk.eth`
    function _dnsEncode(string calldata label) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(label).length), label, WERK_DNS_SUFFIX);
    }
}
