#!/bin/bash

anvil --fork-url $ETH_RPC_URL_MAINNET >/dev/null 2>&1 &
ANVIL_PID=$!
trap "kill $ANVIL_PID >/dev/null 2>&1 || true" EXIT
# wait for anvil to be ready
until curl -s http://localhost:8545 >/dev/null 2>&1; do sleep 0.5; done

DEPLOYER=0xa7ECcdb9Be08178f896c26b7BbD8C3D4E844d9Ba
cast rpc anvil_impersonateAccount $DEPLOYER --rpc-url http://localhost:8545
forge script script/DeployHypMinter.s.sol --rpc-url http://localhost:8545 --unlocked --sender $DEPLOYER --broadcast --sig "run()" -vvvv

MULTISIG_B=0xec2EdC01a2Fbade68dBcc80947F43a5B408cC3A0

# Minter address from DeployHypMinter.s.sol (CREATE2 deterministic address)
export MINTER=0x33a9e84C4437599d2317E6A4e4BEbfFe7fD57E5A
forge script script/SimulateMinting.s.sol --sender $MULTISIG_B --rpc-url http://localhost:8545 --skip-simulation -vvvv

TRANSACTIONS=$(jq '[.transactions[].transaction | {chainId, from, to, gas, value, data: .input}]' ./broadcast/SimulateMinting.s.sol/1/dry-run/run-latest.json)

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
