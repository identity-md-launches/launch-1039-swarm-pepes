# Swarm Pepes (SPEPE)

`src/SwarmPepes.sol:SwarmPepes` is a standard ERC-20 with 18 decimals.
Its argument-free constructor mints **1,000,000,000 SPEPE**, exactly
**1000000000000000000000000000 minor units**, once to `msg.sender`.
A factory deployment therefore gives the entire supply to the factory,
not the account calling that factory.

## Assumptions and behavior

The brief specifies no special transfer rules, so transfers deliver the exact
amount with no tax, burn, rebasing, restrictions, or recipient callbacks.
The implementation inherits OpenZeppelin Contracts v5.0.2 ERC20; the required
sources and license are vendored in `lib/openzeppelin-contracts`.
There are no public mint or burn functions, owner, pause, blacklist, upgrade
mechanism, external services, or initialization calls. Supply remains fixed.

Zero-value and self-transfers follow ERC-20 semantics. Transfers to the zero
address and approvals to a zero spender revert. `transferFrom` requires an
allowance even when called by the deployer. Finite allowances decrease as spent;
the standard maximum-uint256 allowance remains unchanged. Approvals replace the
previous allowance. Holders should approve only the amount needed and revoke
unused allowances; changing an existing approval can race a spender's transaction.

## Build and validation

Install Foundry and Solidity 0.8.26 in the build environment, then run:

```sh
forge build
forge test
forge fmt --check
```

The compiler is version-pinned in `foundry.toml`, with Paris EVM targeting,
optimization at 200 runs, and `bytecode_hash = "none"`. FFI and filesystem
permissions are not enabled. All Solidity dependencies are included; builds
require no dependency downloads once the pinned compiler is available.

Tests cover constructor issuance and its event, direct and factory deployment,
exact transfers, zero/self/full-supply transfers, approval replacement and
revocation, finite/infinite allowances, invalid recipients/spenders, insufficient
balances/allowances, failure rollback, unauthorized spending, absent administrative
entrypoints, and fuzzed conservation and delegated transfers. Tests use isolated
deployments and no environment variables, forks, keys, or network access.

## Deployment and operations

Deploy `src/SwarmPepes.sol:SwarmPepes` directly using its creation bytecode;
constructor arguments are empty (`[]`) and no ETH is required by the contract.
Creation bytecode and ABI can be obtained locally with:

```sh
forge inspect src/SwarmPepes.sol:SwarmPepes bytecode
forge inspect src/SwarmPepes.sol:SwarmPepes abi
```

The network deployer chooses the intended chain and deploying account or factory,
reviews the build parameters, and pays deployment gas. No address configuration
is required by this token. A custom-token launch can deploy this same bytecode
through its factory and perform its distribution and pool transfers unchanged.
Pool parameters, allocation, and launch manifests are managed by that launch
system and are outside this token assignment.

After deployment, verify the name, symbol, decimals, total supply, initial
deployer balance, and source on the target chain. The deployer is responsible for
custody and distribution of its initial balance; holders control their balances
and spender approvals. There are no administrative settings or maintenance
transactions. Tokens sent to an inaccessible address (including this token's
own address) cannot be recovered by an administrator.

Local Foundry checks and security-reference review do not constitute an independent
audit. Obtain an independent adversarial review before release. No transactions
are broadcast by this project; Slither and Mythril were not run.
