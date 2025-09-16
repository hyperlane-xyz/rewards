#!/bin/bash

anvil --rpc-url $(rpc mainnet3 ethereum) >/dev/null 2>&1 &
ANVIL_PID=$!
trap "kill $ANVIL_PID >/dev/null 2>&1 || true" EXIT
# wait for anvil to be ready
until curl -s http://localhost:8545 >/dev/null 2>&1; do sleep 0.5; done

forge script script/DeployHypMinter.s.sol --rpc-url http://localhost:8545 --private-key $(hypkey mainnet3 deployer) -vvvv --broadcast

MULTISIG_B=0xec2EdC01a2Fbade68dBcc80947F43a5B408cC3A0

# Minter address from DeployHypMinter.s.sol (CREATE2 deterministic address)
export MINTER=0x33a9e84C4437599d2317E6A4e4BEbfFe7fD57E5A
forge script script/SimulateMinting.s.sol --sender $MULTISIG_B --rpc-url http://localhost:8545 --skip-simulation -vvvv

TRANSACTIONS=$(jq '[.transactions[].transaction | {chainId, from, to, gas, value, data: .input}]' broadcast/SimulateMinting.s.sol/1/dry-run/run-latest.json)

# Function to create Gnosis transaction format
create_gnosis_batch() {
  local indices="$1"
  echo $TRANSACTIONS | jq --argjson indices "$indices" '{
    version: "1.0",
    chainId: "0x1",
    meta: {},
    transactions: [.[$indices[]]] | map({
      to: .to,
      value: .value,
      data: .data
    })
  }'
}

create_gnosis_batch "[0, 1, 2]" > schedule_transactions.json
create_gnosis_batch "[3]" > execute_network_transactions.json
create_gnosis_batch "[4]" > execute_minter_transactions.json
create_gnosis_batch "[5]" > execute_foundation_transactions.json

kill $ANVIL_PID
