//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    INameWrapper,
    PARENT_CANNOT_CONTROL,
    IS_DOT_ETH
} from "@ensdomains/ens-contracts/contracts/wrapper/INameWrapper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IFixedSubdomainPricer } from "./pricers/IFixedSubdomainPricer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Unavailable();
error Unauthorised(bytes32 node);
error NameNotRegistered();
error InvalidTokenAddress(address);
error NameNotSetup(bytes32 node);
error DataMissing();
error ParentExpired(bytes32 node);
error ParentNotWrapped(bytes32 node);
error DurationTooLong(bytes32 node);
error ParentNameNotSetup(bytes32 parentNode);
error NativeTokenPaymentFailed();

struct Name {
    IFixedSubdomainPricer pricer;
    address beneficiary;
    bool active;
}

abstract contract BaseSubdomainRegistrar {
    using Address for address;

    /// @dev The address of the native token (ETH) following the ERC-7528 standard
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event NameRegistered(bytes32 node, uint256 expiry);
    event NameRenewed(bytes32 node, uint256 expiry);
    event NameSetup(bytes32 node, address pricer, address beneficiary, bool active);

    mapping(bytes32 => Name) public names;
    INameWrapper public immutable wrapper;
    uint64 internal GRACE_PERIOD = 90 days;
    address public immutable authorisedIssuer;

    constructor(address _wrapper, address _authorisedIssuer) {
        wrapper = INameWrapper(_wrapper);
        authorisedIssuer = _authorisedIssuer;
    }

    modifier authorised(bytes32 node) {
        if (!wrapper.canModifyName(node, msg.sender)) {
            revert Unauthorised(node);
        }
        _;
    }

    modifier canBeRegistered(bytes32 parentNode, uint64 duration) {
        _checkParent(parentNode, duration);
        _;
    }

    function available(bytes32 node) public view virtual returns (bool) {
        try wrapper.getData(uint256(node)) returns (address, uint32, uint64 expiry) {
            return expiry < block.timestamp;
        } catch {
            return true;
        }
    }

    function _setupDomain(
        bytes32 node,
        IFixedSubdomainPricer pricer,
        address beneficiary,
        bool active
    )
        internal
        virtual
        authorised(node)
    {
        names[node] = Name({ pricer: pricer, beneficiary: beneficiary, active: active });
        emit NameSetup(node, address(pricer), beneficiary, active);
    }

    function _batchRegister(
        bytes32 parentNode,
        string[] calldata labels,
        address[] calldata addresses,
        address resolver,
        uint16 fuses,
        uint64 duration,
        bytes[][] calldata records
    )
        internal
    {
        if (labels.length != addresses.length || labels.length != records.length) {
            revert DataMissing();
        }

        if (!names[parentNode].active) {
            revert ParentNameNotSetup(parentNode);
        }

        _checkParent(parentNode, duration);

        _batchPayBeneficiary(parentNode, labels);

        // double loop to prevent re-entrancy because _register calls user supplied functions
        for (uint256 i = 0; i < labels.length; i++) {
            _register(
                parentNode, labels[i], addresses[i], resolver, fuses, uint64(block.timestamp) + duration, records[i]
            );
        }
    }

    function register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint32 fuses,
        uint64 duration,
        bytes[] calldata records
    )
        internal
    {
        if (!names[parentNode].active) {
            revert ParentNameNotSetup(parentNode);
        }

        (address asset, uint256 price) = IFixedSubdomainPricer(names[parentNode].pricer).getPriceDetails();

        _checkParent(parentNode, duration);

        if (msg.sender != authorisedIssuer && price > 0) {
            if (asset == NATIVE_TOKEN) {
                (bool success,) = msg.sender.call{ value: price }("");
                if (!success) revert NativeTokenPaymentFailed();
            } else {
                IERC20(asset).transferFrom(msg.sender, address(names[parentNode].beneficiary), price);
            }
        }

        _register(parentNode, label, newOwner, resolver, fuses, uint64(block.timestamp) + duration, records);
    }

    /* Internal Functions */

    function _register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint32 fuses,
        uint64 expiry,
        bytes[] calldata records
    )
        internal
    {
        bytes32 node = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));

        if (!available(node)) {
            revert Unavailable();
        }

        if (records.length > 0) {
            wrapper.setSubnodeOwner(parentNode, label, address(this), 0, expiry);
            _setRecords(node, resolver, records);
        }

        wrapper.setSubnodeRecord(
            parentNode,
            label,
            newOwner,
            resolver,
            0,
            fuses | PARENT_CANNOT_CONTROL, // burn the ability for the parent to control
            expiry
        );

        emit NameRegistered(node, expiry);
    }

    function _batchPayBeneficiary(bytes32 parentNode, string[] calldata labels) internal {
        IFixedSubdomainPricer pricer = names[parentNode].pricer;
        for (uint256 i = 0; i < labels.length; i++) {
            (address token, uint256 price) = pricer.getPriceDetails();
            IERC20(token).transferFrom(msg.sender, names[parentNode].beneficiary, price);
        }
    }

    function _setRecords(bytes32 node, address resolver, bytes[] calldata records) internal {
        for (uint256 i = 0; i < records.length; i++) {
            bytes32 txNamehash = bytes32(records[i][4:36]);
            require(txNamehash == node, "SubdomainRegistrar: Namehash on record do not match the name being registered");
            resolver.functionCall(records[i]);
        }
    }

    function _checkParent(bytes32 parentNode, uint64 duration) internal view {
        uint64 parentExpiry;
        try wrapper.getData(uint256(parentNode)) returns (address, uint32 fuses, uint64 expiry) {
            if (fuses & IS_DOT_ETH == IS_DOT_ETH) {
                expiry = expiry - GRACE_PERIOD;
            }

            if (block.timestamp > expiry) {
                revert ParentExpired(parentNode);
            }
            parentExpiry = expiry;
        } catch {
            revert ParentNotWrapped(parentNode);
        }

        if (duration + block.timestamp > parentExpiry) {
            revert DurationTooLong(parentNode);
        }
    }

    function _setPricer(bytes32 node, IFixedSubdomainPricer pricer) internal {
        names[node].pricer = pricer;
    }
}
