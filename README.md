### https://github.com/Cyfrin/foundry-defi-stablecoin-cu

# What we'll going to build

A stablecoin that is:
1. - Relative Stability: Anchored or Pegged --> $ 1 USD
    1. Chainlink Price Feed
    2. Set a function to exchange ETH & BTC -> $$
2. - Stability Mechanism (minting): Algorithmic (Decentralized)
    1. People can only mint the stablecoin with enough collateral
3. - Collateralization Mechanism: Exogenous (Crypto)
    1. wETH
    2. wBTC (is centrilized?... another conversation)

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
