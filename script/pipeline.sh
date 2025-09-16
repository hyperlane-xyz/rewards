anvil --fork-url $(rpc mainnet3 ethereum) >/dev/null 2>&1 &
ANVIL_PID=$!
trap "kill $ANVIL_PID >/dev/null 2>&1 || true" EXIT
# wait for anvil to be ready
until curl -s http://localhost:8545 >/dev/null 2>&1; do sleep 0.5; done

PRIVATE_KEY=$(hypkey mainnet3 deployer) forge script script/DeployHypMinter.s.sol --rpc-url http://localhost:8545 --broadcast

MINTER=0x33a9e84C4437599d2317E6A4e4BEbfFe7fD57E5A forge script script/SimulateMinting.s.sol --rpc-url http://localhost:8545 -vvvv
