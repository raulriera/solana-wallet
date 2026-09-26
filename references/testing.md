# Testing

- Follow the [Swift Testing expert](plugin://swift-testing-expert@swift-testing-agent-skill)
  skill when writing or reviewing tests.
- Write focused tests for meaningful behavior. Keep happy and failure paths
  separate, test shared behavior once, and name tests after concrete outcomes:
  `get balance returns wallet lamports`, not `get balance is successful`.
- Give public response values explicit public initializers so protocol test
  doubles in other modules can construct immutable, typed fixtures directly.
  Require callers to supply each value, including `nil` for unknown optionals.
- Verify public construction from a consumer using ordinary `import`; `@testable`
  can hide access restrictions. Skip tests that only repeat initializer assignments.
- Use JSON fixtures to verify RPC decoding and typed values for service test doubles.
- Test redaction independently, plus one focused client test proving returned
  errors hide fake credentials. Helper tests alone cannot verify client wiring.
