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

# Deploy the {InvoiceModule} contract deterministically
# See Sablier V2 deployments: https://docs.sablier.com/contracts/v2/deployments
#
# Update the following configs before running the script:
#	- {SABLIER_LOCKUP_LINEAR} with the according {SablierV2LockupLinear} deployment address
#	- {SABLIER_LOCKUP_TRANCHED} with the according {SablierV2LockupTranched} deployment address
#	- {BROKER_ADMIN} with the address of the account managing the Sablier V2 integration fee
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-invoice-module: 
					forge script script/DeployDeterministicInvoiceModule.s.sol:DeployDeterministicInvoiceModule \
					$(CREATE2SALT) {SABLIER_LOCKUP_LINEAR} {SABLIER_LOCKUP_TRANCHED} {BROKER_ADMIN} \
					--sig "run(string,address,address,address)" --rpc-url {RPC_URL} --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) 
					--broadcast --verify


# Deploy a {Container} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {MODULE_KEEPER_ADDRESS} with the address of the {ModuleKeeper} deployment
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-container: 
					forge script script/DeployDeterministicContainer.s.sol:DeployDeterministicContainer \
					$(CREATE2SALT) {INITIAL_OWNER} {MODULE_KEEPER_ADDRESS} [] \
					--sig "run(string,address,address,address[])" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify			

# Deploy a {Container} contract
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {DOCK_REGISTRY} with the address of the {DockRegistr} factory
#	- {DOCK_ID} with the ID of the dock to which the new {Container} will be deployed
# 	- {INITIAL_MODULES} with the addresses of the enabled initial modules (array)
#	- {RPC_URL} with the network RPC used for deployment
deploy-container: 
					forge script script/DeployContainer.s.sol:DeployContainer \
					 {INITIAL_OWNER} {DOCK_REGISTRY} {DOCK_ID} {INITIAL_MODULES} \
					--sig "run(address,address,uint256,address[])" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify	

# Deploy the {ModuleKeeper} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-module-keeper:
					forge script script/DeployDeterministicModuleKeeper.s.sol:DeployDeterministicModuleKeeper \
					$(CREATE2SALT) {INITIAL_OWNER} \
					--sig "run(string,address)" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify

# Deploy the {DockRegistry} contract deterministically 
# Update the following configs before running the script:
#	- {INITIAL_OWNER} with the address of the initial owner
#	- {MODULE_KEEPER} with the address of the {ModuleKeeper} deployment
#	- {ENTRYPOINT} with the address of the {Entrypoiny} contract (currently v6)
#	- {RPC_URL} with the network RPC used for deployment
deploy-deterministic-dock-registry:
					forge script script/DeployDeterministicDockRegistry.s.sol:DeployDeterministicDockRegistry \
					$(CREATE2SALT) {INITIAL_OWNER} {ENTRYPOINT} {MODULE_KEEPER} \
					--sig "run(string,address,address)" --rpc-url {RPC_URL} \
					--private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) \
					--broadcast --verify