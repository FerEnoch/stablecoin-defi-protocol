// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Fer Enoch
 * Collateral: Exogenous (ETH, BTC)
 * Minting (Stability Mechanism): Algorithmic (Decentralized)
 * Value (Relative Stability): Anchored - Pegged to USD
 *
 * @notice This contract meant to be owned (governed) by DSCEngine. This contract is just the ERC20
 * implementation of our stablecoin system. It is a ERC20 token that can be minted and burned by the
 * DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // errors
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor(
        address owner
    ) ERC20("DecentralizedStableCoin", "DSC") Ownable(owner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (_amount <= 0) revert DecentralizedStableCoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }
}
