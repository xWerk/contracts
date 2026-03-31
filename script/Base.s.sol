// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";

contract BaseScript is Script {
    /// @dev The address of the default protocol admin
    address internal constant DEFAULT_PROTOCOL_ADMIN = 0xcaE83b7162d64022f7Da3D011fc96761cB14116a;

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

    /// @dev Across {SpokePool} deployments mapped by the chain ID
    mapping(uint256 chainId => address acrossSpokePool) internal acrossSpokePoolMap;

    /// @dev Werk ENS Subdomain Registrar deployments mapped by the chain ID
    mapping(uint256 chainId => address registrar) internal ensSubdomainRegistrarMap;

    constructor() {
        // Populate the Sablier Lockup deployments map
        populateSablierLockupMap();

        // Populate the Sablier Flow deployments map
        populateSablierFlowMap();

        // Populate the USDC deployments map
        populateUSDCMap();

        // Populate the WETH deployments map
        populateWETHMap();

        // Populate the Across {SpokePool} deployments map
        populateAcrossMap();

        // Populate the Werk ENS Subdomain Registrar deployments map
        // Note: ENS subdomains are issued only on either Base or Base Sepolia
        ensSubdomainRegistrarMap[8453] = 0x959f784aa89311930871545A662F430CCb6DD0Bb;
        ensSubdomainRegistrarMap[84_532] = 0xfd35d5B15780CC6B8ccd8f1Cded4319aC5a63042;
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
        sablierLockupMap[1] = 0xcF8ce57fa442ba50aCbC57147a62aD03873FfA73;

        // Base deployment
        sablierLockupMap[8453] = 0xe261B366f231B12FCB58D6BbD71e57fAEE82431D;

        // HyperEVM deployment
        sablierLockupMap[999] = 0x50ff828e66612A4D1F7141936F2B4078C7356329;

        // Testnets

        // Base Sepolia deployment
        sablierLockupMap[84_532] = 0x5C51EA827Bfa65f7c9AF699e19Ec9fB12A2D40E2;

        // Ethereum Sepolia deployment
        sablierLockupMap[11_155_111] = 0x6b0307b4338f2963A62106028E3B074C2c0510DA;
    }

    /// @dev Populates the Sablier Flow deployments map
    /// See https://docs.sablier.com/guides/flow/deployments
    function populateSablierFlowMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        sablierFlowMap[1] = 0x7a86d3e6894f9c5B5f25FFBDAaE658CFc7569623;

        // Base deployment
        sablierFlowMap[8453] = 0x8551208F75375AbfAEE1FBE0a69e390a94000EC2;

        // HyperEVM deployment
        sablierFlowMap[999] = 0x70ce7795896c1e226C71360F9d77B743d8302182;

        // Testnets

        // Ethereum Sepolia deployment
        sablierFlowMap[11_155_111] = 0xde489096eC9C718358c52a8BBe4ffD74857356e9;

        // Base Sepolia deployment
        sablierFlowMap[84_532] = 0x19e99DCDbAF2fBf43c60cFD026D571860dA29D43;
    }

    /// @dev Populates the USDC deployments map
    /// See https://developers.circle.com/stablecoins/usdc-contract-addresses
    function populateUSDCMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        usdcMap[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Base deployment
        usdcMap[8453] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        // HyperEVM deployment
        usdcMap[999] = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

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

        // HyperEVM deployment
        // Note: WETH is represented as UETH
        wethMap[999] = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;

        // Testnets

        // Ethereum Sepolia deployment
        wethMap[11_155_111] = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

        // Base Sepolia deployment
        wethMap[84_532] = 0x4200000000000000000000000000000000000006;
    }

    /// @dev Populates the Across {SpokePool} deployments map
    /// See https://docs.across.to/reference/contract-addresses
    function populateAcrossMap() internal {
        // Mainnets

        // Ethereum Mainnet deployment
        acrossSpokePoolMap[1] = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;

        // Base deployment
        acrossSpokePoolMap[8453] = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;

        // HyperEVM deployment
        acrossSpokePoolMap[999] = 0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04;

        // Testnets

        // Ethereum Sepolia deployment
        acrossSpokePoolMap[11_155_111] = 0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662;

        // Base Sepolia deployment
        acrossSpokePoolMap[84_532] = 0x82B564983aE7274c86695917BBf8C99ECb6F0F8F;
    }

    /// @notice Generates a salt used for deterministic deployments based on the contract name and a given input salt
    /// @dev ABI encodes the given `contractName` and `inputSalt` strings into a `bytes32` value
    function constructCreate3Salt(
        string memory contractName,
        string memory inputSalt
    )
        internal
        pure
        returns (bytes32)
    {
        return bytes32(abi.encodePacked(contractName, inputSalt));
    }
}
