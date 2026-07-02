// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "test/Base.t.sol";
import { SubscriptionModule } from "src/modules/subscription-module/SubscriptionModule.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";
import { Constants } from "test/utils/Constants.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice Common set-up for the {SubscriptionModule} unit tests
contract SubscriptionModule_Unit_Concrete_Test is Base_Test {
    using MessageHashUtils for bytes32;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    SubscriptionModule internal subscriptionModule;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The trusted backend signer
    address internal subscriptionSigner;
    uint256 internal subscriptionSignerKey;
    /// @dev The treasury that receives all subscription charges
    address internal werkTreasury;

    /// @dev A deterministic mock subscription identifier reused across the suite
    bytes32 internal constant MOCK_SUBSCRIPTION_ID = keccak256("werk.subscription.mock");

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        Base_Test.setUp();

        // Create the trusted backend signer (address + private key) and the treasury
        (subscriptionSigner, subscriptionSignerKey) = makeAddrAndKey("subscriptionSigner");
        werkTreasury = makeAddr("werkTreasury");

        // Deploy the {SubscriptionModule} behind an ERC1967 proxy
        deploySubscriptionModule();

        // Allowlist the {SubscriptionModule} and the {usdt} asset so a {Space} can execute calls on them
        address[] memory subscriptionModules = new address[](2);
        subscriptionModules[0] = address(subscriptionModule);
        subscriptionModules[1] = address(usdt);
        allowlistModules(subscriptionModules);

        // Deploy a new {Space} smart account for Eve
        space = deploySpace({ admin: users.eve });

        // Label the test contracts
        vm.label({ account: address(subscriptionModule), newLabel: "SubscriptionModule" });
        vm.label({ account: subscriptionSigner, newLabel: "SubscriptionSigner" });
        vm.label({ account: werkTreasury, newLabel: "WerkTreasury" });
        vm.label({ account: address(space), newLabel: "Eve's Space" });
    }

    /// @dev Deploys the {SubscriptionModule} module behind an ERC1967 proxy
    function deploySubscriptionModule() internal {
        address implementation = address(new SubscriptionModule());
        bytes memory data = abi.encodeWithSelector(
            SubscriptionModule.initialize.selector, users.admin, subscriptionSigner, werkTreasury
        );
        subscriptionModule = SubscriptionModule(address(new ERC1967Proxy(implementation, data)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Pranks the {Space} owner (Eve) so the following calls flow through `Space.execute`/`executeBatch`
    modifier whenCallerSpace() {
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    modifier givenSubscriptionNotRegistered() {
        _;
    }

    modifier whenValidBackendSignature() {
        _;
    }

    /// @dev Approves the {SubscriptionModule} for the full exposure (`amount * periods`) from Eve's Space
    modifier whenSpaceApprovedModule() {
        uint256 fullExposure = uint256(Constants.SUBSCRIPTION_AMOUNT) * Constants.SUBSCRIPTION_PERIODS;

        bytes memory data =
            abi.encodeWithSignature("approve(address,uint256)", address(subscriptionModule), fullExposure);

        vm.prank({ msgSender: users.eve });
        space.execute({ module: address(usdt), value: 0, data: data });
        _;
    }

    /// @dev Registers the default mock subscription on-chain (approve + subscribe through Eve's Space)
    modifier givenSubscribed() {
        _subscribe(_defaultInput());
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Builds the default mock {SubscribeInput} for Eve's Space paying in USDT
    function _defaultInput() internal view returns (Types.SubscribeInput memory input) {
        input = Types.SubscribeInput({
            subscriptionId: MOCK_SUBSCRIPTION_ID,
            space: address(space),
            interval: Constants.SUBSCRIPTION_INTERVAL,
            periods: Constants.SUBSCRIPTION_PERIODS,
            validUntil: uint40(block.timestamp + Constants.SUBSCRIPTION_QUOTE_TTL),
            asset: address(usdt),
            tier: Constants.SUBSCRIPTION_TIER,
            amount: Constants.SUBSCRIPTION_AMOUNT
        });
    }

    /// @dev Reproduces the exact digest the module rebuilds in `_verifySubscriptionSignature` and signs it with
    /// the trusted backend signer key, returning the EIP-191 signature the module expects
    function _signInput(Types.SubscribeInput memory input) internal view returns (bytes memory signature) {
        bytes32 rawHash = keccak256(
            abi.encode(
                input.subscriptionId,
                input.space,
                input.tier,
                input.asset,
                input.amount,
                input.interval,
                input.periods,
                input.validUntil,
                block.chainid
            )
        );

        bytes32 signedHash = rawHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(subscriptionSignerKey, signedHash);
        signature = abi.encodePacked(r, s, v);
    }

    /// @dev Encodes the calldata for a `subscribe` call on the module
    function _subscribeData(
        Types.SubscribeInput memory input,
        bytes memory signature
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "subscribe((bytes32,address,uint40,uint16,uint40,address,uint8,uint128),bytes)", input, signature
        );
    }

    /// @dev Approves the module for the full exposure and registers the subscription through Eve's Space in one
    /// batch, matching how a real subscription is created (approve + subscribe)
    function _subscribe(Types.SubscribeInput memory input) internal {
        bytes memory signature = _signInput(input);
        uint256 fullExposure = uint256(input.amount) * input.periods;

        address[] memory targets = new address[](2);
        targets[0] = address(usdt);
        targets[1] = address(subscriptionModule);

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(subscriptionModule), fullExposure);
        data[1] = _subscribeData(input, signature);

        vm.prank({ msgSender: users.eve });
        space.executeBatch({ modules: targets, values: values, data: data });
    }
}
