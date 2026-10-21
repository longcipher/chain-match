# Justfile — Foundry project for the Cohort Order Book.
#
# Solidity: src/ (contract, interface, libraries)  Tests: test/
# Scripts:  script/  Dependencies: fetched into dependencies/ by soldeer.
# Run everything:  just ci

# Default recipe to display help
default:
  @just --list

# Format Solidity sources and Markdown
format:
  forge fmt
  rumdl fmt .

# Auto-fix what format cannot
fix:
  rumdl check --fix .
  forge fmt

# Run all lints: formatting, typos, and Markdown
lint:
  forge fmt --check
  typos
  rumdl check --disable MD013 .

# Compile every contract and script
build:
  forge build

# Compile and print the contract size report
check:
  forge build --sizes

# Run the full test suite
test:
  forge test

# Run the test suite with traces
test-verbose:
  forge test -vvv

# Run the tests of one file
test-file path:
  forge test --match-path {{path}}

# Run the invariant campaigns
test-invariant:
  forge test --invariant

# Run the fuzzer with a higher run count
test-fuzz:
  forge test --fuzz-runs 10000

# Report gas usage per test
gas-report:
  forge test --gas-report

# Produce a coverage report
test-coverage:
  forge coverage

# Static analysis with Slither
audit:
  slither .

# Fetch the pinned dependencies into dependencies/
deps:
  soldeer update

# Deploy to a local Anvil node
deploy-local:
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# Run the demo scenario against a local Anvil node
demo-local:
  forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# Fail if Chinese characters appear in the sources or docs
check-cn:
  #!/usr/bin/env bash
  set -uo pipefail
  if rg --line-number --column "\p{Han}" src test script README.md foundry.toml soldeer.config.json; then
    echo "error: Chinese characters found above" >&2
    exit 1
  fi
  echo "ok: no Chinese characters found"

# Full CI check
ci: lint test build

# ============================================================
# Maintenance & Tools
# ============================================================

# Remove build artifacts
clean:
  forge clean

# Install the tools this Justfile needs
setup:
  cargo install --git https://github.com/foundry-rs/foundry --bin forge
  cargo install typos-cli
  cargo install rumdl
  pipx install slither-analyzer
