# Testing

## Coverage

- Follow [Swift Testing Expert](plugin://swift-testing-expert@swift-testing-agent-skill).
  Use Swift Testing for unit tests and XCTest for UI automation.
- Test meaningful outcomes; separate success and failure paths, cover shared behavior once,
  and skip initializer-assignment tests. Use sentence-style names; XCUITests need explicit
  Objective-C selectors for discovery.
- Test internal workflows in app-hosted tests with `@testable` imports.
  Prefer ordinary imports for framework APIs; use existing internal transport or storage
  seams when setup requires them, without widening the production API.
- Use local fixtures for decoding, cryptography, and validation. Check instruction compilation
  against independent SDK fixtures with mixed programs and multiple signers; exercise the app
  consumer through simulation and explicit confirmation.
- Test redaction independently and through one client test using fake credentials.

## Live integrations

- Use real RPC clients; no fake RPCs. Read-only live checks and UI flows use mainnet.
  Tests that fund wallets, submit transactions, or incur fees use devnet, including their
  setup and confirmation. Mainnet-only delivery checks are explicitly opt-in, require
  approval of exact spending limits, and stop if the quote changes.
- Read-only checks use public addresses or published recovery fixtures without accessing
  retained transaction wallets. Compare live values from the same response, isolate mutable
  storage per test, and await cancellation before cleanup. Local fixtures make no network requests.
- Live results do not exhaust provider races or outages. Keep credentials in ignored local
  configuration and recovery out of source, logs, and ordinary files.
- Before funding, save recovery in device-only Vault, read it back, and derive the same address.
  Retain both transfer wallets across runs, reuse balances, and return funds after fees.
  Storage or identity failures stop setup; never replace funded recovery.
- Run funded tests on the retained simulator with `-parallel-testing-enabled NO`; never clone,
  reset, or toggle its biometric enrollment. Follow [biometric-tests](../.agents/skills/biometric-tests/SKILL.md)
  for real biometric checks.

## UI automation

- Follow XCUITest Resilience. Only the user runs UI tests; agents may build without executing
  test setup. Reuse approved simulators and disable parallel execution.
- Make each test self-contained: automatically prepare prerequisites and reset disposable state
  before constructing services. Restrict destructive reset hooks to explicit Debug simulator
  test launches; preserve state during relaunches that verify persistence.
- Exercise production services at normal storage locations. Use public fixtures or disposable,
  unfunded generated wallets whose words may appear in user-run screenshots. Never use existing
  or funded recovery in UI automation.
- Query visible text and accessibility labels, scoping by native container only when needed.
  Do not add test-only accessibility identifiers; incorrect user-facing labels must fail.
- Check readiness before acting. Unexpected setup alerts fail immediately; never mask them
  with generic timeouts, automatic dismissal, or blind retries of committed actions.
