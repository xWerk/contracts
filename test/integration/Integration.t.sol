// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../Base.t.sol";
import { PaymentModule } from "./../../src/modules/payment-module/PaymentModule.sol";
import { InvoiceCollection } from "./../../src/peripherals/invoice-collection/InvoiceCollection.sol";
import { WerkSubdomainRegistrar } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistrar.sol";
import { WerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/WerkSubdomainRegistry.sol";
import { IWerkSubdomainRegistry } from "./../../src/peripherals/ens-domains/interfaces/IWerkSubdomainRegistry.sol";
import { SablierV2LockupLinear } from "@sablier/v2-core/src/SablierV2LockupLinear.sol";
import { SablierV2LockupTranched } from "@sablier/v2-core/src/SablierV2LockupTranched.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockNFTDescriptor } from "../mocks/MockNFTDescriptor.sol";
import { MockStreamManager } from "../mocks/MockStreamManager.sol";
import { MockBadSpace } from "../mocks/MockBadSpace.sol";
import { ud } from "@prb/math/src/UD60x18.sol";
import { Space } from "./../../src/Space.sol";

abstract contract Integration_Test is Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    PaymentModule internal paymentModule;
    InvoiceCollection internal invoiceCollection;
    // Sablier V2 related test contracts
    MockNFTDescriptor internal mockNFTDescriptor;
    SablierV2LockupLinear internal sablierV2LockupLinear;
    SablierV2LockupTranched internal sablierV2LockupTranched;
    MockStreamManager internal mockStreamManager;
    MockBadSpace internal badSpace;
    WerkSubdomainRegistrar internal werkSubdomainRegistrar;
    WerkSubdomainRegistry internal werkSubdomainRegistry;

    address[] internal modules;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        Base_Test.setUp();

        // Deploy corect contracts
        deployCoreContracts();

        // Enable the {PaymentModule} and {WerkSubdomainRegistrar} modules on the {Space} contract
        modules.push(address(paymentModule));
        modules.push(address(werkSubdomainRegistrar));

        // Allowlist the required modules for testing
        allowlistModules(modules);

        // Deploy the {Space} contract with the {PaymentModule} enabled by default
        space = deploySpace({ _owner: users.eve, _stationId: 0 });

        // Deploy a "bad" {Space} with the `mockBadReceiver` as the owner
        badSpace = deployBadSpace({ _owner: address(mockBadReceiver), _stationId: 0 });

        // Label the test contracts so we can easily track them
        vm.label({ account: address(paymentModule), newLabel: "PaymentModule" });
        vm.label({ account: address(sablierV2LockupLinear), newLabel: "SablierV2LockupLinear" });
        vm.label({ account: address(sablierV2LockupTranched), newLabel: "SablierV2LockupTranched" });
        vm.label({ account: address(space), newLabel: "Eve's Space" });
        vm.label({ account: address(badSpace), newLabel: "Bad receiver's Space" });
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT-RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys the core contracts of the Werk Protocol
    function deployCoreContracts() internal {
        deployPaymentModule();
        deployInvoiceCollection();
        deployWerkSubdomainRegistrar();
    }

    /// @dev Deploys the {PaymentModule} module
    function deployPaymentModule() internal {
        deploySablierContracts();

        address implementation = address(new PaymentModule(sablierV2LockupLinear, sablierV2LockupTranched));
        bytes memory data = abi.encodeWithSelector(PaymentModule.initialize.selector, users.admin, users.admin, ud(0));
        paymentModule = PaymentModule(address(new ERC1967Proxy(implementation, data)));
    }

    /// @dev Deploys the {InvoiceCollection} peripheral
    function deployInvoiceCollection() internal {
        invoiceCollection =
            new InvoiceCollection({ _relayer: users.admin, _name: "Werk Invoice NFTs", _symbol: "WERK-INVOICES" });
    }

    /// @dev Deploys the Sablier v2-required contracts
    function deploySablierContracts() internal {
        mockNFTDescriptor = new MockNFTDescriptor();
        sablierV2LockupLinear =
            new SablierV2LockupLinear({ initialAdmin: users.admin, initialNFTDescriptor: mockNFTDescriptor });
        sablierV2LockupTranched = new SablierV2LockupTranched({
            initialAdmin: users.admin,
            initialNFTDescriptor: mockNFTDescriptor,
            maxTrancheCount: 1000
        });
    }

    /// @dev Deploys the {WerkSubdomainRegistrar} L2 ENS registrar
    function deployWerkSubdomainRegistrar() internal {
        // Deploy the {WerkSubdomainRegistry} registry
        werkSubdomainRegistry = new WerkSubdomainRegistry();

        // Initialize the {WerkSubdomainRegistry} registry
        werkSubdomainRegistry.initialize("werk.eth", "werk.eth", "https://werk.com/");

        // Deploy the {WerkSubdomainRegistrar} registrar
        werkSubdomainRegistrar = new WerkSubdomainRegistrar({
            _registry: IWerkSubdomainRegistry(address(werkSubdomainRegistry)),
            _owner: users.admin
        });

        // Add the {WerkSubdomainRegistrar} as a registrar to the {WerkSubdomainRegistry}
        werkSubdomainRegistry.addRegistrar({ registrar: address(werkSubdomainRegistrar) });
    }
}
