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
					$(CREATE2SALT) {RELAYER} {NAME} {SYMBOL} \
					--sig "run(address,string,string)" --rpc-url {RPC_URL} --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify

# Deploys the {ModuleKeeper} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-module-keeper:
					forge script script/DeployDeterministicModuleKeeper.s.sol:DeployDeterministicModuleKeeper \
					$(CREATE2SALT) {INITIAL_OWNER} \
					--sig "run(string,address)" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify

# Deploys the {StationRegistry} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {ENTRYPOINT} with the address of the {Entrypoiny} contract (currently v6)
#	- {MODULE_KEEPER} with the address of the {ModuleKeeper} deployment
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-dock-registry:
					forge script script/DeployDeterministicStationRegistry.s.sol:DeployDeterministicStationRegistry \
					$(CREATE2SALT) {INITIAL_OWNER} {ENTRYPOINT} {MODULE_KEEPER} \
					--sig "run(string,address,address)" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify