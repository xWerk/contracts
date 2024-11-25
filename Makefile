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
deploy-invoice-collection: 
					forge script script/DeployInvoiceCollection.s.sol:DeployInvoiceCollection \
					{RELAYER} {NAME} {SYMBOL} \
					--sig "run(address,string,string)" --rpc-url {RPC_URL} --account dev --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify

# Deploys the {ModuleKeeper} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-module-keeper:
					forge script script/DeployDeterministicModuleKeeper.s.sol:DeployDeterministicModuleKeeper \
					$(CREATE2SALT) {INITIAL_OWNER} \
					--sig "run(string,address)" --rpc-url {RPC_URL} \
					--account dev --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify

# Deploys the {StationRegistry} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {ENTRYPOINT} with the address of the {Entrypoint} contract (currently v6)
#	- {MODULE_KEEPER} with the address of the {ModuleKeeper} deployment
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-dock-registry:
					forge script script/DeployDeterministicStationRegistry.s.sol:DeployDeterministicStationRegistry \
					$(CREATE2SALT) {INITIAL_OWNER} {ENTRYPOINT} {MODULE_KEEPER} \
					--sig "run(string,address,address)" --rpc-url {RPC_URL} \
					--account dev --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify

# Deploys the {PaymentModule} contract deterministically 
#
# Update the following configs before running the script:
#	- {SABLIER_LOCKUP_LINEAR} with the according {SablierV2LockupLinear} deployment address
#	- {SABLIER_LOCKUP_TRANCHED} with the according {SablierV2LockupTranched} deployment address
#	- {INITIAL_OWNER} with the address of the initial admin of the {PaymentModule}
#	- {BROKER_ACCOUNT} with the address of the account responsible for collecting the broker fees (multisig vault)
#	- {RPC_URL} with the network RPC used for deployment
deploy-payment-module: 
					forge script script/DeployDeterministicPaymentModule.s.sol:DeployDeterministicPaymentModule \
					$(CREATE2SALT) {SABLIER_LOCKUP_LINEAR} {SABLIER_LOCKUP_TRANCHED} {INITIAL_OWNER} {BROKER_ACCOUNT} \
					--sig "run(string,address,address,address,address)" --rpc-url {RPC_URL} --account dev --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify	

# Deploys the {PaymentModule} contract deterministically 

# Deploys the core contracts deterministically 
#
# Update the following configs before running the script:
#	- {SABLIER_LOCKUP_LINEAR} with the according {SablierV2LockupLinear} deployment address
#	- {SABLIER_LOCKUP_TRANCHED} with the according {SablierV2LockupTranched} deployment address
#	- {INITIAL_OWNER} with the address of the initial admin of the {StationRegistry} and {PaymentModule}
#	- {BROKER_ACCOUNT} with the address of the account responsible for collecting the broker fees (multisig vault)
#	- {ENTRYPOINT} with the address of the {Entrypoint} contract (currently v6)
#	- {RPC_URL} with the network RPC used for deployment
deploy-core: 
					forge script script/DeployDeterministicCore.s.sol:DeployDeterministicCore \
					$(CREATE2SALT) "0xfe7fc0bbde84c239c0ab89111d617dc7cc58049f" "0xb8c724df3ec8f2bf8fa808df2cb5dbab22f3e68c" "0x85E094B259718Be1AF0D8CbBD41dd7409c2200aa" "0x85E094B259718Be1AF0D8CbBD41dd7409c2200aa" "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789" \
					--sig "run(string,address,address,address,address,address)" --rpc-url https://sepolia.base.org --account dev \
					--broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --ffi				