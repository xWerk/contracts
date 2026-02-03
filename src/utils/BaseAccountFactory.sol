// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Utils
import { Multicall } from "@thirdweb/contracts/extension/Multicall.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";
import { BytesLib } from "@thirdweb/contracts/lib/BytesLib.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Interface
import { IAccountFactory } from "./../interfaces/IAccountFactory.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

/// Note: Fork of the thirdweb `BaseAccountFactory.sol` contract which allows the `createAccount`
/// method to be overriden in child contracts
abstract contract BaseAccountFactory is IAccountFactory, Multicall, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.BaseAccountFactoryStorage
    struct BaseAccountFactoryStorage {
        /// @notice The address of the Account implementation
        address accountImplementation;
        /// @notice The address of the Entrypoint V6
        address entrypoint;
        /// @notice List holding all accounts of this factory
        EnumerableSet.AddressSet allAccounts;
        /// @notice Mapping holding all accounts of a signer
        mapping(address => EnumerableSet.AddressSet) accountsOfSigner;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.BaseAccountFactoryStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_ACCOUNT_FACTORY_STORAGE_LOCATION =
        0xd479a1cdcdff4d5b32b49ac922bb23f23b5e2197c27de6189f536624c7299000;

    /// @dev Retrieves the storage of the {BaseAccountFactoryStorage} contract
    function _getBaseAccountFactoryStorage() internal pure returns (BaseAccountFactoryStorage storage $) {
        assembly {
            $.slot := BASE_ACCOUNT_FACTORY_STORAGE_LOCATION
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Internal initializer for proxy-based deployments
    function __BaseAccountFactory_init(address _accountImpl, address _entrypoint) internal onlyInitializing {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        $.accountImplementation = _accountImpl;
        $.entrypoint = _entrypoint;
    }

    /*///////////////////////////////////////////////////////////////
                        Public functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Account for admin.
    function createAccount(address _admin, bytes calldata _data) public virtual override returns (address) {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        // Cache the Account implementation address
        address impl = $.accountImplementation;

        // Construct the salt used for the deterministic deployment
        bytes32 salt = _generateSalt(_admin, _data);

        // Encode initialization data for the proxy
        bytes memory initData = abi.encodeWithSignature("initialize(address,bytes)", _admin, _data);

        // Predict the Account proxy address
        address account = _predictProxyAddress(impl, initData, salt);

        // Return early if there's an already deployed account at the predicted address
        if (account.code.length > 0) {
            return account;
        }

        // Add account to allAccounts BEFORE deployment to allow callbacks during initialization
        if (msg.sender != $.entrypoint) {
            require($.allAccounts.add(account), "AccountFactory: account already registered");
        }

        // Deploy the ERC1967Proxy at a deterministic address and initialize it
        account = address(new ERC1967Proxy{ salt: salt }(impl, initData));

        return account;
    }

    /*///////////////////////////////////////////////////////////////
                        External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback function for an Account to register itself on the factory.
    function onRegister() external {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        address account = msg.sender;
        require(_isAccountOfFactory(account), "AccountFactory: not an account.");

        require($.allAccounts.add(account), "AccountFactory: account already registered");
    }

    function onSignerAdded(address _signer) external {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        address account = msg.sender;
        require(_isAccountOfFactory(account), "AccountFactory: not an account.");

        bool isNewSigner = $.accountsOfSigner[_signer].add(account);

        if (isNewSigner) {
            emit SignerAdded(account, _signer);
        }
    }

    /// @notice Callback function for an Account to un-register its signers.
    function onSignerRemoved(address _signer) external {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        address account = msg.sender;
        require(_isAccountOfFactory(account), "AccountFactory: not an account.");

        bool isAccount = $.accountsOfSigner[_signer].remove(account);

        if (isAccount) {
            emit SignerRemoved(account, _signer);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the account implementation.
    function accountImplementation() external view returns (address) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.accountImplementation;
    }

    /// @notice Returns the address of the entrypoint.
    function entrypoint() external view returns (address) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.entrypoint;
    }

    /// @notice Returns whether an account is registered on this factory.
    function isRegistered(address _account) external view returns (bool) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.allAccounts.contains(_account);
    }

    /// @notice Returns the total number of accounts.
    function totalAccounts() external view returns (uint256) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.allAccounts.length();
    }

    /// @notice Returns all accounts between the given indices.
    function getAccounts(uint256 _start, uint256 _end) external view returns (address[] memory accounts) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        require(_start < _end && _end <= $.allAccounts.length(), "BaseAccountFactory: invalid indices");

        uint256 len = _end - _start;
        accounts = new address[](_end - _start);

        for (uint256 i = 0; i < len; i += 1) {
            accounts[i] = $.allAccounts.at(i + _start);
        }
    }

    /// @notice Returns all accounts created on the factory.
    function getAllAccounts() external view returns (address[] memory) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.allAccounts.values();
    }

    /// @notice Returns the address of an Account that would be deployed with the given admin signer.
    function getAddress(address _adminSigner, bytes calldata _data) public view returns (address) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        bytes32 salt = _generateSalt(_adminSigner, _data);
        bytes memory initData = abi.encodeWithSignature("initialize(address,bytes)", _adminSigner, _data);
        return _predictProxyAddress($.accountImplementation, initData, salt);
    }

    /// @notice Returns all accounts that the given address is a signer of.
    function getAccountsOfSigner(address signer) external view returns (address[] memory accounts) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.accountsOfSigner[signer].values();
    }

    /// @notice Retrieves the total number of accounts created by the `signer` address
    function totalAccountsOfSigner(address signer) public view returns (uint256) {
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();
        return $.accountsOfSigner[signer].length();
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns whether the caller is an account deployed by this factory.
    function _isAccountOfFactory(address _account) internal view virtual returns (bool) {
        // Retrieve the storage of the {StreamManager} contract
        BaseAccountFactoryStorage storage $ = _getBaseAccountFactoryStorage();

        // With ERC1967Proxy, we can't predict the address without the init data,
        // so we check if the account is registered in the allAccounts set
        return $.allAccounts.contains(_account);
    }

    function _getImplementation(address cloneAddress) internal view returns (address) {
        bytes memory code = cloneAddress.code;
        return BytesLib.toAddress(code, 10);
    }

    /// @dev Returns the salt used when deploying an Account.
    function _generateSalt(address _admin, bytes memory _data) internal view virtual returns (bytes32) {
        return keccak256(abi.encode(_admin, _data));
    }

    /// @dev Predicts the address of an ERC1967Proxy deployed via CREATE2
    function _predictProxyAddress(
        address _impl,
        bytes memory _initData,
        bytes32 _salt
    )
        internal
        view
        returns (address)
    {
        bytes memory proxyBytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_impl, _initData));

        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(proxyBytecode)))))
        );
    }
}
