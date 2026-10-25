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
- Check workflow models through their typed state, such as a rejection case, not message text.
- Call the code under test and derive expected values independently: published specs, SDK or
  reference-implementation fixtures, or hand-worked examples. Never compute them with the
  production formula, a copy of it, or the function under test. Assertions on fixtures alone
  only guard that filtering leaves vectors covered.
- Don't restate source: skip assertions that a constant, method name, raw value, or one-line
  predicate's truth table equals the literals the source declares; test the behavior that uses
  it. Literals with outside authority, such as program IDs, wire encodings, provider endpoints,
  and persisted names, are valid expectations.
- Test values headlessly through models, formatters, and plans; don't render views to read them
  back. Don't assert SwiftUI or UIKit behavior the app can't change, such as rendered sizes, font
  metrics, presentation timing, or system expiry. Move logic out of views until it runs without a
  window, and verify layout in the simulator.
- Use local fixtures for decoding, cryptography, and validation. Check instruction compilation
  against independent SDK fixtures with mixed programs and multiple signers; exercise the app
  consumer through simulation, explicit submission, and confirmation.
- Test redaction independently and through one client test using fake credentials.

## Test plans

Pass the existing regular iPhone simulator to every command, such as `-destination 'platform=iOS Simulator,id=<UUID>'`.

- `Unit`, the `widgets` scheme's default plan, runs the app's `widgetsTests` bundle and every framework's
  test bundle offline. Run it for every change: `xcodebuild test -scheme widgets`.
- Each framework's scheme runs only its own offline test bundle; the `Portfolio` scheme also runs `RPCTests`.
  Use it to iterate on one framework: `xcodebuild test -scheme <Framework>`, such as `-scheme Transactions`.
- `Integration` runs only tests tagged `.network`:
  `xcodebuild test -scheme widgets -testPlan Integration -parallel-testing-enabled NO`.
  Run it only when a change touches the RPC, Transactions, or Portfolio frameworks, or the app's
  provider, account discovery, portfolio, or transaction workflows, or when the user asks.
- `UI` runs `widgetsUITests` without parallel clones:
  `xcodebuild test -scheme widgets -testPlan UI -parallel-testing-enabled NO`. Only the user runs it, on request.
- Tag every test that sends a request to a real provider with `.network`: on its suite, or on the test
  in a suite that mixes local and live tests. Framework test bundles stay offline; put their live
  checks in `App/Tests/Integration/<Framework>`.

## Live integrations

- Use real RPC clients; no fake RPCs. Read-only live checks and UI flows use mainnet; a read-only check may use devnet for behavior that only devnet runs yet, such as Alpenglow.
  Tests that fund wallets, submit transactions, or incur fees use devnet, including their
  setup and confirmation. Mainnet-only delivery checks are explicitly opt-in, require
  approval of exact spending limits, and stop if the quote changes.
- Read-only checks use public addresses or published recovery fixtures without accessing
  retained transaction wallets. Compare live values from the same response, isolate mutable
  storage per test, and await cancellation before cleanup. Local fixtures make no network requests.
- Live results do not exhaust provider races or outages. Keep credentials, including your
  devnet test wallet's seed, in ignored local configuration; keep recovery out of source and logs.
- Funded devnet tests send from account 0 to account 1 of that seed, never create wallets, and
  leave the funds with account 1; refill account 0 manually when it runs low. A missing seed or
  an unfunded sender stops setup.
- Follow [biometric-tests](../.agents/skills/biometric-tests/SKILL.md) for real biometric checks.

## UI automation

- Follow the [XCUITest Best Practices](plugin://skills@raulriera) skill (`xcuitest-best-practices`). Reuse approved
  simulators and disable parallel execution.
- Make each test self-contained: automatically prepare prerequisites and reset disposable state
  before constructing services. Restrict destructive reset hooks to explicit Debug simulator
  test launches; preserve state during relaunches that verify persistence.
- Check scene restoration by hand: send the app to the background before stopping it. Ending the
  app in the foreground discards its saved scene state, so UI tests do not cover restoration.
- Exercise production services at normal storage locations. Use public fixtures or disposable,
  unfunded generated wallets whose words may appear in user-run screenshots. Never use existing
  or funded recovery in UI automation.
- Query visible text and accessibility labels, scoping by native container only when needed.
  Do not add test-only accessibility identifiers; incorrect user-facing labels must fail.
- Do not write tests that only check accessibility, such as accessibility audits or label
  assertions. Use the Xcode accessibility skills for accessibility reviews.
- Check readiness before acting. Unexpected setup alerts fail immediately; never mask them
  with generic timeouts, automatic dismissal, or blind retries of committed actions.
