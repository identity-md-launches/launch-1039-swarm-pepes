// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../src/SwarmPepes.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SPEPETestSupport, SPEPEActor} from "./helpers/SPEPETestSupport.sol";

/// forge-config: default.fuzz.runs = 1000
contract SwarmPepesAdversarialTest is SPEPETestSupport {
    SwarmPepes private token;
    address private owner;
    address private spender;
    address private recipient;
    address private outsider;

    function setUp() public {
        owner = address(new SPEPEActor());
        spender = address(new SPEPEActor());
        recipient = address(new SPEPEActor());
        outsider = address(new SPEPEActor());
        vm.prank(owner);
        token = new SwarmPepes();
    }

    function testOneWeiThenRemainingSupplyCanBeSpentExactlyOnce() public {
        _approve(SUPPLY);
        vm.prank(spender);
        require(token.transferFrom(owner, recipient, 1), "one wei transfer");
        require(token.balanceOf(recipient) == 1, "one wei not received");
        vm.prank(spender);
        require(token.transferFrom(owner, recipient, SUPPLY - 1), "remaining supply transfer");
        require(token.balanceOf(owner) == 0, "owner not emptied");
        require(token.balanceOf(recipient) == SUPPLY, "supply arrived short");
        require(token.allowance(owner, spender) == 0, "allowance not exhausted");

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        require(token.balanceOf(recipient) == SUPPLY, "repeat spend changed balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testMaximumTransferAmountsRevertWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        vm.prank(owner);
        token.transfer(recipient, type(uint256).max);

        _approve(type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, type(uint256).max);
        _assertUntouched(type(uint256).max);
    }

    function testMaximumMinusOneAllowanceIsFinite() public {
        _approve(type(uint256).max - 1);
        vm.prank(spender);
        require(token.transferFrom(owner, recipient, 1), "spend");
        require(token.allowance(owner, spender) == type(uint256).max - 2, "finite allowance treated as infinite");
        require(token.balanceOf(owner) == SUPPLY - 1, "owner debit");
        require(token.balanceOf(recipient) == 1, "recipient credit");
    }

    function testInfiniteAllowanceCanBeReplacedAndRevokedAfterSpending() public {
        _approve(type(uint256).max);
        vm.prank(spender);
        require(token.transferFrom(owner, recipient, 1), "infinite spend");
        require(token.allowance(owner, spender) == type(uint256).max, "infinite allowance changed");
        _approve(2);
        vm.prank(spender);
        require(token.transferFrom(owner, recipient, 1), "finite spend");
        require(token.allowance(owner, spender) == 1, "finite allowance not decremented");
        _approve(0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        require(token.balanceOf(recipient) == 2, "revoked spend delivered tokens");
        require(token.balanceOf(owner) == SUPPLY - 2, "revoked spend debited owner");
        require(token.allowance(owner, spender) == 0, "revocation changed");
    }

    function testZeroTransfersEmitEventsWithoutBalanceOrAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(outsider, recipient, 0);
        vm.prank(outsider);
        require(token.transfer(recipient, 0), "zero direct transfer");

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(outsider, recipient, 0);
        vm.prank(spender);
        require(token.transferFrom(outsider, recipient, 0), "zero delegated transfer");
        require(token.balanceOf(outsider) == 0, "empty holder changed");
        require(token.allowance(outsider, spender) == 0, "zero transfer created allowance");
        _assertUntouched(0);
    }

    function testZeroAmountDoesNotMakeZeroAddressesValid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), 0);

        // Rejection is the property; validation order may report an invalid approver or sender.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 0);
        require(token.balanceOf(address(0)) == 0, "zero address acquired tokens");
        require(token.allowance(owner, address(0)) == 0, "zero address acquired allowance");
        _assertUntouched(0);
    }

    function testAllowanceCannotBeUsedByAnotherSpenderOrForAnotherOwner() public {
        _approve(type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(owner, recipient, 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(outsider, recipient, 1);
        _assertUntouched(type(uint256).max);
    }

    function testFuzzTransferOverBalanceIsAtomic(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        vm.prank(owner);
        require(token.transfer(outsider, balance), "fund holder");
        uint256 amount = bound(rawExcess, balance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, outsider, balance, amount)
        );
        vm.prank(outsider);
        token.transfer(recipient, amount);
        require(token.balanceOf(outsider) == balance, "failure debited holder");
        require(token.balanceOf(owner) == SUPPLY - balance, "failure changed other holder");
        require(token.balanceOf(recipient) == 0, "failure credited recipient");
        require(token.totalSupply() == SUPPLY, "failure changed supply");
    }

    function testFuzzTransferFromOverAllowanceIsAtomic(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowed = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, allowed + 1, SUPPLY);
        _approve(allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
        _assertUntouched(allowed);
    }

    function testFuzzFailedTransferFromRestoresFiniteOrInfiniteAllowance(uint256 rawBalance, bool infinite) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        vm.prank(owner);
        require(token.transfer(outsider, SUPPLY - balance), "reduce owner balance");
        uint256 amount = balance + 1;
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
        require(token.allowance(owner, spender) == allowed, "failed call consumed allowance");
        require(token.balanceOf(owner) == balance, "failed call debited owner");
        require(token.balanceOf(recipient) == 0, "failed call credited recipient");
        require(token.balanceOf(outsider) == SUPPLY - balance, "failed call changed other holder");
        require(token.totalSupply() == SUPPLY, "failed call changed supply");
    }

    function testFuzzDelegatedSelfTransferPreservesBalanceButConsumesAllowance(uint256 rawAmount, bool infinite)
        public
    {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        _approve(infinite ? type(uint256).max : amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(owner, owner, amount);
        vm.prank(spender);
        require(token.transferFrom(owner, owner, amount), "self transfer");
        _assertUntouched(infinite ? type(uint256).max : 0);
    }

    function testFuzzTransfersRoundTripWithoutFees(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(owner);
        require(token.transfer(recipient, amount), "outbound transfer");
        require(token.balanceOf(recipient) == amount, "outbound arrived short");
        vm.prank(recipient);
        require(token.transfer(owner, amount), "return transfer");
        _assertUntouched(0);
    }

    function _approve(uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "approval");
    }

    function _assertUntouched(uint256 allowance) private view {
        require(token.balanceOf(owner) == SUPPLY, "owner balance changed");
        require(token.balanceOf(recipient) == 0, "recipient balance changed");
        require(token.balanceOf(spender) == 0, "spender balance changed");
        require(token.allowance(owner, spender) == allowance, "allowance changed");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }
}
