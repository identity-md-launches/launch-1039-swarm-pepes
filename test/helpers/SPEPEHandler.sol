// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../../src/SwarmPepes.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SPEPETestSupport, SPEPEActor} from "./SPEPETestSupport.sol";

/// @dev All token movement stays within four actors, including the deploying contract.
/// Ghost accounting uses requested transfers, never observed balances, as its oracle.
contract SPEPEHandler is SPEPETestSupport {
    uint256 public constant ACTOR_COUNT = 4;
    uint256 public constant STARTING_BALANCE = SUPPLY / ACTOR_COUNT;
    SwarmPepes public immutable token;
    address[4] public actors;
    mapping(address => uint256) public sent;
    mapping(address => uint256) public received;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public checkedReverts;

    constructor() {
        token = new SwarmPepes();
        actors[0] = address(this);
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            actors[i] = address(new SPEPEActor());
            require(token.transfer(actors[i], STARTING_BALANCE), "seed actor");
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(rawAmount, _balance(from));
        vm.prank(from);
        require(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
        if (amount > 0 && from != to) ++positiveTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(rawAmount, 0, SUPPLY);
        else amount = rawAmount;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @dev Spends the allowance left by earlier calls, including exhausted/replaced approvals.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 maximum = _balance(owner);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < maximum) maximum = allowed;
        _spend(owner, spender, _actor(toSeed), _amount(rawAmount, maximum));
    }

    /// @dev Ensures nonzero delegated movement is reachable without a lucky approval sequence.
    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAmount,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(rawAmount, _balance(owner));
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _spend(owner, spender, _actor(toSeed), amount);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
        ++checkedReverts;
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = _balance(from);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        ++checkedReverts;
    }

    function transferFromTooMuchBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAmount,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = _balance(owner);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // No ghost debit: the preceding approval must survive the failed transfer unchanged.
        ++checkedReverts;
    }

    function transferFromTooMuchAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        _approve(owner, spender, amount - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        ++checkedReverts;
    }

    function invalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(rawAmount, _balance(owner));
        if (mode % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (mode % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), rawAmount);
        } else {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
        ++checkedReverts;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _balance(address actor) private view returns (uint256) {
        return STARTING_BALANCE + received[actor] - sent[actor];
    }

    /// @dev Exercise zero, one wei and the entire balance frequently, plus arbitrary amounts.
    function _amount(uint256 rawAmount, uint256 maximum) private pure returns (uint256) {
        if (rawAmount % 4 == 0) return 0;
        if (rawAmount % 4 == 1) return maximum == 0 ? 0 : 1;
        if (rawAmount % 4 == 2) return maximum;
        return bound(rawAmount, 0, maximum);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        require(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        _recordTransfer(owner, to, amount);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
        if (amount > 0 && owner != to) ++positiveDelegatedTransfers;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }
}
