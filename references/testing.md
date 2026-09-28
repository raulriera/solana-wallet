# Testing

- Follow the [Swift Testing expert](plugin://swift-testing-expert@swift-testing-agent-skill)
  skill when writing or reviewing tests.
- Write focused tests for meaningful behavior. Keep happy and failure paths
  separate, test shared behavior once, and name tests after concrete outcomes:
  `get balance returns wallet lamports`, not `get balance is successful`.
- Verify RPC integrations with the actual clients on devnet, including submission
  and confirmation. Do not add fake RPC implementations. Keep test credentials in
  ignored local configuration and recovery material out of source, logs, and disk.
- Verify public construction from a consumer using ordinary `import`; `@testable`
  can hide access restrictions. Keep implementation helpers internal; don't make
  them public for tests. Skip tests that only repeat initializer assignments.
- Test internal app workflows in app-hosted `widgetsTests` using `@testable import widgets`;
  continue using ordinary imports for their framework contracts and response values.
- Use local fixtures for decoding, cryptography, and validation. Live tests prove
  observed network behavior; do not claim they exhaust provider races or outages.
- Test redaction independently, plus one focused client test proving returned
  errors hide fake credentials. Helper tests alone cannot verify client wiring.
