-include .env

# Build contracts
build :; forge build

# Run tests
run-tests :; forge test

# Clean build contracts
clean :; forge clean

# Generate coverage stats using lcov and genhtml
# See https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/coverage.sh
tests-coverage :; ./script/coverage.sh

# Deploys the {InvoiceCollection} peripheral 
#
# Update the following configs before running the script:
#	- {RELAYER} with the address of the Relayer responsible to mint the invoice NFTs
#	- {NAME} with the name of the ERC-721 {InvoiceCollection} contract
#	- {SYMBOL} with symbol of the ERC-721 {InvoiceCollection} contract
#	- {RPC_URL} with the network RPC used for deployment
#	- {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-invoice-collection: 
					forge script script/DeployInvoiceCollection.s.sol:DeployInvoiceCollection \
					$(RELAYER) $(NAME) $(SYMBOL) \
					--sig "run(address,string,string)" --rpc-url {RPC_URL} --account dev --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify

# Deploys the {ModuleKeeper} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {RPC_URL} with the network RPC used for deployment
#	- {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-deterministic-module-keeper:
					forge script script/DeployDeterministicModuleKeeper.s.sol:DeployDeterministicModuleKeeper \
					$(CREATE2SALT) $(INITIAL_OWNER) \
					--sig "run(string,address)" --rpc-url $(RPC_URL) \
					--account dev --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify

# Deploys the {StationRegistry} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {ENTRYPOINT} with the address of the {Entrypoint} contract (currently v6)
#	- {MODULE_KEEPER} with the address of the {ModuleKeeper} deployment
#	- {RPC_URL} with the network RPC used for deployment
#	- {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-deterministic-station-registry:
					forge script script/DeployDeterministicStationRegistry.s.sol:DeployDeterministicStationRegistry \
					$(CREATE2SALT) $(INITIAL_OWNER) $(ENTRYPOINT) $(MODULE_KEEPER) \
					--sig "run(string,address,address,address)" --rpc-url $(RPC_URL) \
					--account dev --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify --ffi

# Deploys the {PaymentModule} contract deterministically 
#
# Update the following configs before running the script:
#	- {SABLIER_LOCKUP_LINEAR} with the according {SablierV2LockupLinear} deployment address
#	- {SABLIER_LOCKUP_TRANCHED} with the according {SablierV2LockupTranched} deployment address
#	- {INITIAL_OWNER} with the address of the initial admin of the {PaymentModule}
#	- {BROKER_ACCOUNT} with the address of the account responsible for collecting the broker fees (multisig vault)
#	- {RPC_URL} with the network RPC used for deployment
#	- {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-payment-module: 
					forge script script/DeployDeterministicPaymentModule.s.sol:DeployDeterministicPaymentModule \
					$(CREATE2SALT) $(SABLIER_LOCKUP_LINEAR) $(SABLIER_LOCKUP_TRANCHED) $(INITIAL_OWNER) $(BROKER_ACCOUNT) \
					--sig "run(string,address,address,address,address)" --rpc-url $(RPC_URL) --account dev --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify	

# Deploys the core contracts deterministically 
#
# Update the following configs before running the script:
#	- {SABLIER_LOCKUP_LINEAR} with the according {SablierV2LockupLinear} deployment address
#	- {SABLIER_LOCKUP_TRANCHED} with the according {SablierV2LockupTranched} deployment address
#	- {INITIAL_OWNER} with the address of the initial admin of the {StationRegistry} and {PaymentModule}
#	- {BROKER_ACCOUNT} with the address of the account responsible for collecting the broker fees (multisig vault)
#	- {ENTRYPOINT} with the address of the {Entrypoint} contract (currently v6)
#	- {RPC_URL} with the network RPC used for deployment
#	- {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-core: 
					forge script script/DeployDeterministicCore.s.sol:DeployDeterministicCore \
					$(CREATE2SALT) $(SABLIER_LOCKUP_LINEAR) $(SABLIER_LOCKUP_TRANCHED) $(INITIAL_OWNER) $(BROKER_ACCOUNT) $(ENTRYPOINT) \
					--sig "run(string,address,address,address,address,address)" --rpc-url $(RPC_URL) --account dev \
					--broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --ffi

# Deploys the {WerkSubdomainCore} contract deterministically 
#
# Update the following configs before running the script:
#   - {WERK_SUBDOMAIN_ENS_DOMAIN} with the ENS domain name of the {WerkSubdomainRegistry}
#   - {WERK_SUBDOMAIN_BASE_URI} with the base URI of the {WerkSubdomainRegistry}
#   - {INITIAL_OWNER} with the address of the initial registry owner
#   - {RPC_URL} with the network RPC used for deployment
#   - {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-ens-subdomain-core:
					forge script script/ens-domains/DeployDeterministicWerkSubdomainCore.s.sol:DeployDeterministicWerkSubdomainCore \
					$(CREATE2SALT) "werk.eth" $(WERK_SUBDOMAIN_BASE_URI) $(INITIAL_OWNER) \
					--sig "run(string,string,string,address)" --rpc-url $(RPC_URL) --account dev \
					--broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)
					
# Deploys the {L2SubdomainRegistrar} contract deterministically 
#
# Update the following configs before running the script:
#   - {WERK_SUBDOMAIN_REGISTRY} with the address of the {WerkSubdomainRegistry} contract 
#   - {RPC_URL} with the network RPC used for deployment
#   - {INITIAL_OWNER} with the address of the initial registrar owner
#   - {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
deploy-ens-subdomain-registrar:
					forge script script/ens-domains/DeployDeterministicWerkSubdomainRegistrar.s.sol:DeployDeterministicWerkSubdomainRegistrar \
                    $(CREATE2SALT) $(WERK_SUBDOMAIN_REGISTRY) $(INITIAL_OWNER) \
                    --sig "run(string,address,address)" --rpc-url $(RPC_URL) --account dev \
                    --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)

# Configure the {WerkSubdomainRegistry} to allow the {WerkSubdomainRegistrar} to register subdomains
configure-ens-subdomain-registry:
                    cast send $(WERK_SUBDOMAIN_REGISTRY) "addRegistrar(address)" $(WERK_SUBDOMAIN_REGISTRAR) --rpc-url $(RPC_URL) --acount dev 

# Upgrades the {PaymentModule} contract
#
# Update the following configs before running the script:
#   - {PAYMENT_MODULE_PROXY} with the address of the {PaymentModule} proxy on the target chain
#   - {SABLIER_LOCKUP_LINEAR} with the address of the {SablierV2LockupLinear} deployment on the target chain
#   - {SABLIER_LOCKUP_TRANCHED} with the address of the {SablierV2LockupTranched} deployment on the target chain
#   - {RPC_URL} with the network RPC used for deployment
#   - {ETHERSCAN_API_KEY} with the Etherscan API key on the target chain
upgrade-payment-module:
					forge script script/upgrade/UpgradePaymentModule.s.sol:UpgradePaymentModule \
					$(PAYMENT_MODULE_PROXY) $(SABLIER_LOCKUP_LINEAR) $(SABLIER_LOCKUP_TRANCHED) \
					--sig "run(address,address,address)" --rpc-url $(RPC_URL) --account dev \
					--broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --ffi