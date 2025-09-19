MULTISIG_B=0xec2EdC01a2Fbade68dBcc80947F43a5B408cC3A0


forge script script/SimulateOwnershipTransfer.s.sol \
--sender $MULTISIG_B \
--rpc-url mainnet \
--skip-simulation \
-vvvv


TRANSACTIONS=$(jq '[.transactions[] | {chainId: .transaction.chainId, to: .transaction.to, gas: .transaction.gas, value: .transaction.value, data: .transaction.input, function: .function}]' \
./broadcast/SimulateOwnershipTransfer.s.sol/1/dry-run/run-latest.json)
echo $TRANSACTIONS

create_gnosis_batch() {
  local function_filter="$1"
  
  # Filter by function signature
  echo $TRANSACTIONS | jq --arg func "$function_filter" '{
    version: "1.0",
    chainId: "0x1", 
    meta: {},
    transactions: [.[] | select(.function | startswith($func))] | map({
      to: .to,
      value: .value,
      data: .data,
    })
  }'
}

create_gnosis_batch "schedule" > ./script/calldata/schedule_transactions_timelock.json
