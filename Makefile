# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

.PHONY: test

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
tuni   :; forge test -w -v --evm-version shanghai --match-contract TraderUniSepoliaTest
taero   :; forge test -w -vvvvv --evm-version shanghai --match-contract TraderAeroSepoliaTest
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fm