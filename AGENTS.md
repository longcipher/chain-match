# chain-match Agent Instructions

## Non-negotiables

- Surgical edits only: every changed line must trace to the request. No drive-by refactors, no reformatting untouched code, no deleting pre-existing dead code (mention it instead).
- Fix root causes. Never silence a warning, weaken a check, or patch a symptom to make a gate pass.
- Never report completion while any `just` gate below fails. Report the failure verbatim and stop.
- Stop and ask when a request is ambiguous, conflicts with existing conventions, or requires credentials, publishing, or destructive operations.
- When a correction reveals a missing rule, add one specific rule here ("always X for Y", never "be careful with Y"); delete rules that never catch real errors.

## Scope

- `chain-match` is a Foundry project for `CohortOrderBook`: a fully on-chain limit order book that keeps order placement, cancellation, and cohort matching at O(1) by grouping same-price, same-generation orders into fungible "cohorts".
- `src/CohortOrderBook.sol` is the main contract; `src/interfaces/ICohortOrderBook.sol` holds the shared enums, structs, events, and custom errors; `src/libraries/` holds `PriceLevelTree`, `CohortManager`, and `OrderBookMath`.
- `test/` has four Foundry suites mirroring that layout — `CohortOrderBook.t.sol`, `CohortOrderBook.e2e.t.sol`, `test/libraries/OrderBookMath.t.sol`, `test/libraries/PriceLevelTree.t.sol`.
- `script/Deploy.s.sol` deploys to a local Anvil node; `script/Demo.s.sol` drives a market-making / market-order / cancel scenario against a deployed instance. Both use the well-known Anvil test key — never reuse that key on a public network.
- `foundry.toml` is the single source of build settings: `via_ir = true`, optimizer on with 200 runs, 120-column formatting, 4-space indent, `bracket_spacing = true`.
- Dependencies are pinned by `soldeer.config.json` and fetched into `dependencies/` (gitignored) — `forge-std` 1.9.4 and `openzeppelin-contracts` 5.1.0.
- English only in code, comments, docs, and commit messages.

## Execution

- Parallelize aggressively: dispatch subagents for independent research, exploration, and implementation.
- The three libraries are independent of each other — change and test them in parallel; the main contract depends on all three, so sequence that work last.
- NEVER use `git worktree`. Edit the current branch in place.
- TDD for behavior changes: write the failing Foundry test first, make the smallest change that passes it, then run the whole `just test` suite.

## Verification loop

After each feature or bug fix, in order; any failure means the task is not done:

```bash
just format
just lint
just test
```

`format` runs `forge fmt` plus `rumdl fmt`; `lint` runs `forge fmt --check`, `typos`, and `rumdl check`; `test` runs `forge test`. `just ci` additionally compiles the contracts.

## Foundry rules

- Solidity is `^0.8.24`; never lower the pragma and never add an unchecked-arithmetic block without a written justification.
- Every state-changing external function carries `nonReentrant` (OpenZeppelin `ReentrancyGuard`); `emergencyCancel` is the only owner-gated mutator and `onlyOwner` compares against the `owner` state variable set in the constructor.
- `receive()` must keep reverting — the book holds no ETH.
- Signal failures with the custom errors declared in `ICohortOrderBook` (`InvalidPrice`, `InvalidAmount`, `OrderNotFound`, `OrderNotActive`, `UnauthorizedCancellation`, `InsufficientLiquidity`, `InvalidGeneration`, `PriceLevelDoesNotExist`, `CohortDoesNotExist`). Do not introduce new `require` strings.
- Prices are `uint96` and amounts are bounded by `MAX_AMOUNT = type(uint128).max`; `MIN_PRICE` is 1. Keep the price and amount scales at 1e18 in the API.
- The O(1) guarantee is the whole point: do not add a loop over price levels, cohorts, or trader orders to a placement, cancellation, or matching path. `getOrderBookDepth` is the one deliberate O(n) view.
- Keep the generation model intact: cohorts are keyed by `(price, generation)`, the generation advances per block for time priority, and fills inside a cohort are proportional to each order's contribution.
- `PriceLevelTree` is a sorted doubly-linked list, not a tree — insert and remove at known neighbours, and keep the cached best bid/ask in sync with the list head.
- Every new behaviour needs a test in the matching `test/` file; use `forge test --match-path test/<file>.t.sol` while iterating.

## Dependency choices

- Foundry (`forge`, `anvil`, `cast`) is the toolchain; `soldeer` fetches the pinned dependencies into `dependencies/`.
- `forge-std` for tests and scripting, `@openzeppelin/contracts` for `ReentrancyGuard` and any future standard-library primitive. Both are pinned in `soldeer.config.json` — change the version there, never in an import path.
- `rumdl` lints the Markdown, `typos` scans prose, `slither` provides the static-analysis pass. Do not add a Solidity linter that the repo does not already run.
- Prefer a library over hand-rolled logic for anything already solved in OpenZeppelin 5.1.

## Code conventions

- `forge fmt` is the only formatter: 120 columns, 4-space indent, spaces inside brackets.
- NatSpec on every external function and every struct; state variables grouped by concern with `// ===` banner comments.
- Tests are `contract XTest is Test` with `function test_<behaviour>()` naming, and assertion helpers come from `forge-std/Test.sol`.
- Update `README.md` when the public API, error set, or complexity claims change — it is the only interface documentation in the repo.
