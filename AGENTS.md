# Project constraints

- Keep this file lean: user-approved restrictions and clarifications only.
- Use Conventional Commits format for every commit.
- Do not add module-name prefixes to types; rely on the module namespace.
- Keep project files grouped by concern in real folders that Xcode mirrors; group related tests accordingly.
- Keep every approach Simple, Easy to change, Don't Repeat Yourself, and Single Concern.
- Use protocol-oriented programming throughout: depend on protocols and inject concrete implementations.
- iOS 27.1+ with full iPhone Duo support; no older-iOS compatibility paths.
- Swift 6 with the latest compiler, SDK APIs, Apple guidance, and supported upcoming language features. No deprecated approaches.
- Pure Swift and Apple frameworks; avoid third-party dependencies where reasonable.
- Follow the Swift Concurrency plugin's `swift-concurrency` skill.
- Follow [references/testing.md](references/testing.md) when writing or reviewing tests.
- Document every function and initializer using Apple DocC conventions.
- Solana V1 transactions only.
- Separate frameworks by concern; all Helius communication belongs in the RPC/API framework.
- The RPC module exposes a provider-neutral protocol; Helius is a concrete implementation.
- Add RPC methods only for concrete needs of agreed wallet features; follow [references/rpc-scope.md](references/rpc-scope.md), not endpoint coverage.
- Helius is the only live Solana RPC provider; no app-owned backend/proxy.
- Use Helius DAS for all portfolio data; follow [references/portfolio.md](references/portfolio.md).
- Keep wallet recovery material device-only, excluded from iCloud sync and backups; follow [references/wallet.md](references/wallet.md).
- Agree on architecture before implementation; work on one concern at a time.
- Request documentation as Markdown by appending `.md`. Apple API docs: `https://developer.apple.com/documentation/<path>.md`; tutorials/design guidance: `https://developer.apple.com/tutorials/data/<path>.md`.

Keep [references/](references/) concise and free of unapproved designs.
