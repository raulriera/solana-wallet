# Testing

## Coverage

- Follow [Swift Testing Expert](plugin://swift-testing-expert@swift-testing-agent-skill): Swift Testing for unit tests, XCTest for UI automation. XCUITests need explicit Objective-C selectors.
- Test meaningful outcomes. Separate success and failure paths, cover shared behavior once, and skip initializer-assignment tests.
- Test internal workflows in app-hosted tests with `@testable` imports. Use ordinary imports for framework APIs, and existing transport or storage seams without widening the production API.
- Check workflow models through their typed state, such as a rejection case, not message text.
- Derive expected values independently: published specs, SDK fixtures, or hand-worked examples. Never compute them with the production formula or the function under test.
- Literals with outside authority, such as program IDs, wire encodings, and endpoints, are valid expectations, not restated source.
- Test values headlessly through models and formatters, not rendered views. Don't assert system behavior the app can't change, such as font metrics or presentation timing; verify layout in the simulator.
- Check instruction compilation against independent SDK fixtures with mixed programs and several signers.

## Test plans

Pass the existing regular iPhone simulator to every command, such as `-destination 'platform=iOS Simulator,id=<UUID>'`.

- `Unit`, the `widgets` scheme's default plan, runs the app and framework test bundles offline. Run it for every change: `xcodebuild test -scheme widgets`. Add every new test bundle to it.
- `Integration` runs only `.network` tests: `xcodebuild test -scheme widgets -testPlan Integration -parallel-testing-enabled NO`. Run it when a change touches the RPC framework, Transactions, Portfolio, or the app's RPC, price, discovery, portfolio, or transaction workflows.
- `UI` runs `widgetsUITests`. Only the user runs it, on request.
- Tag every test that reaches a real provider with `.network`. Framework bundles stay offline; their live checks go in `App/Tests/Integration/<Framework>`.

## Live integrations

- A read-only check may use devnet for behavior only devnet has yet, such as Alpenglow.
- Funded devnet tests send from account 0 to account 1 of the ignored local seed and leave the funds there. A missing seed or an unfunded sender stops setup.
- Read-only checks use public addresses or published fixtures. Compare live values from one response, isolate storage per test, and await cancellation before cleanup.

## UI automation

- Follow the [XCUITest Best Practices](plugin://skills@raulriera) skill (`xcuitest-best-practices`).
- Each test prepares its own state before services start. Destructive reset hooks run only in explicit Debug simulator test launches.
- Use public fixtures or disposable unfunded wallets; never existing or funded recovery.
- Query visible text and accessibility labels. Add no test-only identifiers and no accessibility-only tests.
- Unexpected alerts fail at once; never hide them with timeouts, automatic dismissal, or retries of committed actions.
- UI tests can't cover scene restoration; check it by hand by sending the app to the background before stopping it.
