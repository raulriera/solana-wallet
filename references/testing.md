# Testing

- Follow the [Swift Testing expert](plugin://swift-testing-expert@swift-testing-agent-skill)
  skill when writing or reviewing tests.
- Write focused tests for meaningful behavior. Keep happy and failure paths
  separate, test shared behavior once, and name tests after concrete outcomes:
  `get balance returns wallet lamports`, not `get balance is successful`.
- Give response values in cross-module contracts explicit public initializers so
  protocol test doubles can construct immutable, typed fixtures directly.
  Require callers to supply each value, including `nil` for unknown optionals.
- Verify public construction from a consumer using ordinary `import`; `@testable`
  can hide access restrictions. Keep implementation helpers internal; don't make
  them public for tests. Skip tests that only repeat initializer assignments.
- Test internal app workflows in app-hosted `widgetsTests` using `@testable import widgets`;
  continue using ordinary imports for their framework contracts and response values.
- Use JSON fixtures to verify RPC decoding and typed values for service test doubles.
- Test redaction independently, plus one focused client test proving returned
  errors hide fake credentials. Helper tests alone cannot verify client wiring.
