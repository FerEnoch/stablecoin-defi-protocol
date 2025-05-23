# Descentralized Stablecoin
### This is part of the Smart Contracts Development course of Cyfrin Updraft
### https://github.com/Cyfrin/foundry-defi-stablecoin-cu

## What is this repository?
This repository contains the code for a decentralized stablecoin built using Foundry. The goal is to create a stablecoin that is pegged to the US dollar, using an algorithmic minting mechanism and collateralized by other cryptocurrencies.

## The Stablecoin design:
1. *-* Relative Stability: Anchored or Pegged to $ 1 USD
    - We're using Chainlink Price Feed.
2. *-* Stability Mechanism (minting): Algorithmic (Decentralized)
    - People can only mint the stablecoin with enough collateral
3. *-* Collateralization Mechanism: Exogenous (Crypto)
    - wETH
    - wBTC

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
