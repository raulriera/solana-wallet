# Testing

- Follow the [Swift Testing expert](plugin://swift-testing-expert@swift-testing-agent-skill)
  skill when writing or reviewing tests.
- Write focused tests for meaningful behavior. Keep happy and failure paths
  separate, test shared behavior once, and name tests after concrete outcomes:
  `get balance returns wallet lamports`, not `get balance is successful`.
- Verify RPC integrations with the actual clients on devnet, including submission
  and confirmation. Do not add fake RPC implementations. Keep test credentials in
  ignored local configuration and recovery material out of source, logs, and ordinary files.
- Before requesting any funding, save test recovery in the device-only Vault and
  verify it by reading back and deriving the same address. Retain both ends of
  funded transfers across runs, reuse their balances, and return funds after fees.
  Storage or identity failures stop setup; never silently replace a funded wallet.
  Run funded tests on the retained simulator with `-parallel-testing-enabled NO`;
  disposable simulator clones and resets cannot retain control of funded accounts.
- For tests needing real biometrics, follow the local
  [biometric-tests skill](../.agents/skills/biometric-tests/SKILL.md). It explains
  local simulator selection, enrollment commands, opt-in tests, and
  authentication events. Never toggle enrollment on the retained wallet simulator.
- Verify public construction from a consumer using ordinary `import`; `@testable`
  can hide access restrictions. Keep implementation helpers internal; don't make
  them public for tests. Skip tests that only repeat initializer assignments.
- Verify generic instruction compilation against independent SDK fixtures, including mixed programs and multiple signers. Exercise the app consumer through simulation and explicit confirmation; test shared validation once.
- Test internal app workflows in app-hosted `widgetsTests` using `@testable import widgets`;
  continue using ordinary imports for their framework contracts and response values.
- Use local fixtures for decoding, cryptography, and validation. Live tests prove
  observed network behavior; do not claim they exhaust provider races or outages.
- Test redaction independently, plus one focused client test proving returned
  errors hide fake credentials. Helper tests alone cannot verify client wiring.
