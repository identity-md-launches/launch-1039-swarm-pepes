// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface SPEPEVm {
    function prank(address caller) external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

// These contracts represent local test holders, not launch configuration.
contract SPEPEActor {}

/// @dev Matches the existing suite's dependency-free use of Foundry cheatcodes.
abstract contract SPEPETestSupport {
    SPEPEVm internal constant vm = SPEPEVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev Inclusive bounds without discarded fuzz cases; retains inputs already in range.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        return minimum + value % (maximum - minimum + 1);
    }
}
