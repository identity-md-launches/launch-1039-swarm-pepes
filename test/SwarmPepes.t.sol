// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../src/SwarmPepes.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

interface Vm {
    function prank(address caller) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
}

contract TokenDeployer {
    function deploy() external returns (SwarmPepes) {
        return new SwarmPepes();
    }
}

contract SwarmPepesTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    SwarmPepes private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SwarmPepes();
    }

    function testMetadataAndInitialSupply() public view {
        require(keccak256(bytes(token.name())) == keccak256("Swarm Pepes"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("SPEPE"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY, "supply");
        require(token.balanceOf(address(this)) == SUPPLY, "deployer balance");
        require(token.balanceOf(ALICE) == 0, "unexpected balance");
    }

    function testConstructorMintsToContractDeployerAndEmitsEvent() public {
        TokenDeployer factory = new TokenDeployer();
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(factory), SUPPLY);
        SwarmPepes deployed = factory.deploy();
        require(deployed.balanceOf(address(factory)) == SUPPLY, "factory balance");
        require(deployed.balanceOf(address(this)) == 0, "caller is not deployer");
    }

    function testTransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), ALICE, 100 ether);
        require(token.transfer(ALICE, 100 ether), "transfer result");
        require(token.balanceOf(ALICE) == 100 ether, "recipient balance");
        require(token.balanceOf(address(this)) == SUPPLY - 100 ether, "sender balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFullSupplyCanMoveAndReturn() public {
        require(token.transfer(ALICE, SUPPLY), "full transfer");
        vm.prank(ALICE);
        require(token.transfer(address(this), SUPPLY), "return transfer");
        require(token.balanceOf(address(this)) == SUPPLY, "returned balance");
        require(token.balanceOf(ALICE) == 0, "remaining balance");
    }

    function testZeroAndSelfTransfersPreserveBalances() public {
        require(token.transfer(ALICE, 0), "zero transfer");
        require(token.transfer(address(this), SUPPLY), "self transfer");
        require(token.balanceOf(address(this)) == SUPPLY, "self balance");
        require(token.balanceOf(ALICE) == 0, "zero balance");
    }

    function testApproveAndTransferFromConsumeAllowance() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), ALICE, 50 ether);
        require(token.approve(ALICE, 50 ether), "approval result");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, 20 ether), "delegated transfer");
        require(token.allowance(address(this), ALICE) == 30 ether, "remaining allowance");
        require(token.balanceOf(BOB) == 20 ether, "recipient balance");
        require(token.balanceOf(address(this)) == SUPPLY - 20 ether, "sender balance");
    }

    function testApprovalCanBeReplacedAndRevoked() public {
        require(token.approve(ALICE, 10 ether), "approve");
        require(token.approve(ALICE, 3 ether), "replace");
        require(token.allowance(address(this), ALICE) == 3 ether, "replacement");
        require(token.approve(ALICE, 0), "revoke");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
    }

    function testInfiniteAllowanceUsesStandardERC20Semantics() public {
        require(token.approve(ALICE, type(uint256).max), "approve");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, 1 ether), "transfer");
        require(token.allowance(address(this), ALICE) == type(uint256).max, "infinite allowance");
    }

    function testTransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        require(token.balanceOf(address(this)) == SUPPLY, "failed transfer changed balance");
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function testInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        require(token.balanceOf(BOB) == 0, "failure delivered tokens");
    }

    function testInsufficientAllowanceRevertsWithoutStateChange() public {
        require(token.approve(ALICE, 2), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 2, 3));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 3);
        require(token.allowance(address(this), ALICE) == 2, "allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
        require(token.balanceOf(BOB) == 0, "recipient changed");
    }

    function testTransferFromBalanceFailureRestoresAllowance() public {
        vm.prank(ALICE);
        require(token.approve(address(this), 5), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 5));
        token.transferFrom(ALICE, BOB, 5);
        require(token.allowance(ALICE, address(this)) == 5, "allowance not restored");
    }

    function testTransferFromToZeroRestoresAllowance() public {
        require(token.approve(ALICE, 1), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(address(this), address(0), 1);
        require(token.allowance(address(this), ALICE) == 1, "allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
    }

    function testDeployerCannotSpendHolderTokensWithoutApproval() public {
        require(token.transfer(ALICE, 100 ether), "fund holder");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        vm.prank(ALICE);
        require(token.transfer(BOB, 100 ether), "holder remains free to transfer");
    }

    function testNoMintBurnOrAdministrativeEntrypoints() public {
        bytes[7] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", address(this), 1),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("initialize(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            require(!ok, "unexpected privileged entrypoint");
            vm.prank(ALICE);
            (ok,) = address(token).call(calls[i]);
            require(!ok, "unexpected public entrypoint");
        }
        require(token.totalSupply() == SUPPLY, "supply changed");
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
    }

    function testFuzzTransfersConserveSupply(uint256 rawAmount, uint256 rawReturn) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        uint256 returned = rawReturn % (amount + 1);
        require(token.transfer(ALICE, amount), "transfer");
        vm.prank(ALICE);
        require(token.transfer(BOB, returned), "second transfer");
        require(token.balanceOf(ALICE) == amount - returned, "alice");
        require(token.balanceOf(BOB) == returned, "bob");
        require(token.balanceOf(address(this)) == SUPPLY - amount, "deployer");
        require(
            token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB) == SUPPLY, "conservation"
        );
        require(token.totalSupply() == SUPPLY, "supply");
    }

    function testFuzzDelegatedTransfer(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowed = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (allowed + 1);
        require(token.approve(ALICE, allowed), "approve");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, amount), "transfer");
        require(token.allowance(address(this), ALICE) == allowed - amount, "allowance");
        require(token.balanceOf(BOB) == amount, "recipient");
        require(token.balanceOf(address(this)) == SUPPLY - amount, "sender");
        require(token.totalSupply() == SUPPLY, "supply");
    }
}
