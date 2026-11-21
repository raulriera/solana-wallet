# Testing

## Coverage

- Follow [Swift Testing Expert](https://github.com/AvdLee/Swift-Testing-Agent-Skill): Swift Testing for unit tests, XCTest for UI automation. XCUITests need explicit Objective-C selectors.
- Test only the app's own functionality, offline or in UI tests; never test a provider's API.
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
- `UI` runs `widgetsUITests`. Only the user runs it, on request.

## UI automation

- Follow the [XCUITest Best Practices](https://github.com/raulriera/skills/tree/main/xcuitest-best-practices) skill (`xcuitest-best-practices`).
- Each test prepares its own state before services start. Destructive reset hooks run only in explicit Debug simulator test launches.
- Query visible text and accessibility labels. Add no test-only identifiers and no accessibility-only tests.
- Unexpected alerts fail at once; never hide them with timeouts, automatic dismissal, or retries of committed actions.
- UI tests can't cover scene restoration; check it by hand by sending the app to the background before stopping it.
