// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";
import { ud, UD60x18 } from "@prb/math/src/UD60x18.sol";

contract BaseScript is Script {
    /// @dev The address of the default protocol owner
    address internal constant DEFAULT_PROTOCOL_OWNER = 0x85E094B259718Be1AF0D8CbBD41dd7409c2200aa;

    /// @dev The address of the default broker account for {FlowStreamManager} and {LockupStreamManager} contracts
    address internal constant DEFAULT_BROKER_ADMIN = 0x85E094B259718Be1AF0D8CbBD41dd7409c2200aa;

    /// @dev The default broker fee for {FlowStreamManager} and {LockupStreamManager} contracts
    UD60x18 internal DEFAULT_BROKER_FEE = ud(0);

    /// @dev The address of the Entrypoint v6 deployment
    address internal constant ENTRYPOINT_V6 = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    /// @dev Sablier Lockup deployments mapped by the chain ID
    mapping(uint256 chainId => address sablierLockup) internal sablierLockupMap;

    /// @dev Sablier Flow deployments mapped by the chain ID
    mapping(uint256 chainId => address sablierFlow) internal sablierFlowMap;

    /// @dev USDC deployments mapped by the chain ID
    mapping(uint256 chainId => address USDC) internal usdcMap;

    /// @dev WETH deployments mapped by the chain ID
    mapping(uint256 chainId => address WETH) internal wethMap;

    constructor() {
        // Populate the Sablier Lockup deployments map
        populateSablierLockupMap();

        // Populate the Sablier Flow deployments map
        populateSablierFlowMap();

        // Populate the USDC deployments map
        populateUSDCMap();

        // Populate the WETH deployments map
        populateWETHMap();
    }

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    /// @dev Populates the Sablier Lockup deployments map
    /// See https://docs.sablier.com/guides/lockup/deployments
    function populateSablierLockupMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        sablierLockupMap[1] = 0x7C01AA3783577E15fD7e272443D44B92d5b21056;

        // Base deployment
        sablierLockupMap[8453] = 0xb5D78DD3276325f5FAF3106Cc4Acc56E28e0Fe3B;

        // Testnets

        // Base Sepolia deployment
        sablierLockupMap[84_532] = 0xa4777CA525d43a7aF55D45b11b430606d7416f8d;

        // Ethereum Sepolia deployment
        sablierLockupMap[11_155_111] = 0xd116c275541cdBe7594A202bD6AE4DBca4578462;
    }

    /// @dev Populates the Sablier Flow deployments map
    /// See https://docs.sablier.com/guides/flow/deployments
    function populateSablierFlowMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        sablierFlowMap[1] = 0x3DF2AAEdE81D2F6b261F79047517713B8E844E04;

        // Base deployment
        sablierFlowMap[8453] = 0x6FE93c7f6cd1DC394e71591E3c42715Be7180A6A;

        // Testnets

        // Ethereum Sepolia deployment
        sablierFlowMap[11_155_111] = 0x93FE8f86e881a23e5A2FEB4B160514Fd332576A6;

        // Base Sepolia deployment
        sablierFlowMap[84_532] = 0xFB6B72a5988A7701a9090C56936269241693a9CC;
    }

    /// @dev Populates the USDC deployments map
    /// See https://developers.circle.com/stablecoins/usdc-on-test-networks
    /// and https://developers.circle.com/stablecoins/usdc-on-main-networkss
    function populateUSDCMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        usdcMap[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Base deployment
        usdcMap[8453] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        // Testnets

        // Ethereum Sepolia deployment
        usdcMap[11_155_111] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

        // Base Sepolia deployment
        usdcMap[84_532] = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    }

    /// @dev Populates the WETH deployments map
    function populateWETHMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        wethMap[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // Base deployment
        wethMap[8453] = 0x4200000000000000000000000000000000000006;

        // Testnets

        // Ethereum Sepolia deployment
        wethMap[11_155_111] = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

        // Base Sepolia deployment
        wethMap[84_532] = 0x4200000000000000000000000000000000000006;
    }
}
