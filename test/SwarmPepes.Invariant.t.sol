// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../src/SwarmPepes.sol";
import {SPEPEHandler} from "./helpers/SPEPEHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmPepesInvariantTest {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SPEPEHandler private handler;
    SwarmPepes private token;

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new SPEPEHandler();
        token = handler.token();
    }

    // Foundry's invariant discovery ABI. Explicit targeting prevents direct token calls
    // from bypassing the handler's accounting; no forge-std installation is required.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = SPEPEHandler.transfer.selector;
        selectors[1] = SPEPEHandler.approve.selector;
        selectors[2] = SPEPEHandler.transferFrom.selector;
        selectors[3] = SPEPEHandler.approveAndTransferFrom.selector;
        selectors[4] = SPEPEHandler.revokeAndAttemptSpend.selector;
        selectors[5] = SPEPEHandler.transferTooMuch.selector;
        selectors[6] = SPEPEHandler.transferFromTooMuchBalance.selector;
        selectors[7] = SPEPEHandler.transferFromTooMuchAllowance.selector;
        selectors[8] = SPEPEHandler.invalidAddress.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// @notice The one constructor mint must remain the total, with every token accounted for.
    function invariant_supplyIsFixedAndBalancesConserveIt() public view {
        require(token.totalSupply() == SUPPLY, "fixed supply changed");
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        require(sum == SUPPLY, "balances do not conserve supply");
        require(token.balanceOf(address(0)) == 0, "zero address holds tokens");
    }

    /// @notice Each holder retains exactly its initial funding plus net authorized transfers.
    function invariant_eachHolderMatchesTransferHistory() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            require(
                token.balanceOf(actor) + handler.sent(actor) == handler.STARTING_BALANCE() + handler.received(actor),
                "holder balance differs from transfer history"
            );
        }
    }

    /// @notice Approvals remain isolated by owner/spender, finite budgets shrink only on success,
    /// and maximum approvals persist until explicitly replaced or revoked.
    function invariant_allowancesMatchApprovalAndSpendingHistory() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            require(token.allowance(owner, address(0)) == 0, "zero spender has allowance");
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(owner, spender) == handler.expectedAllowance(owner, spender),
                    "allowance differs from approval/spending history"
                );
            }
        }
    }

    /// @dev Deterministic reachability check for every handler, including meaningful transfers.
    /// This also makes failures in the harness easier to distinguish from token defects.
    function testHandlerExercisesSuccessfulAndRejectedCalls() public {
        _checkAll();
        handler.transfer(0, 1, 7);
        _checkAll();
        handler.approve(1, 2, 9, 2);
        _checkAll();
        handler.transferFrom(1, 2, 3, 7);
        _checkAll();
        handler.approveAndTransferFrom(3, 2, 0, 7, true);
        _checkAll();
        handler.revokeAndAttemptSpend(3, 2, 0);
        _checkAll();
        handler.transferTooMuch(0, 1, type(uint256).max);
        _checkAll();
        handler.transferFromTooMuchBalance(1, 2, 3, type(uint256).max - 1, false);
        _checkAll();
        handler.transferFromTooMuchAllowance(1, 2, 3, 9);
        _checkAll();
        for (uint8 mode; mode < 3; ++mode) {
            handler.invalidAddress(0, 1, 7, mode);
            _checkAll();
        }
        require(handler.positiveTransfers() == 1, "direct movement not exercised");
        require(handler.positiveDelegatedTransfers() == 2, "delegated movement not exercised");
        require(handler.checkedReverts() == 7, "rejections not exercised");
    }

    /// @dev After each random sequence, every holder must still be able to transfer its full balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < handler.ACTOR_COUNT(); ++i) {
            handler.transfer(i, 0, 2); // The handler maps 2 to the entire available balance.
            _checkAll();
        }
        require(token.balanceOf(handler.actors(0)) == SUPPLY, "holders could not return the entire supply");
    }

    function _checkAll() private view {
        invariant_supplyIsFixedAndBalancesConserveIt();
        invariant_eachHolderMatchesTransferHistory();
        invariant_allowancesMatchApprovalAndSpendingHistory();
    }
}
