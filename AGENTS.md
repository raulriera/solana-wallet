# Project constraints

- Keep this file lean: user-approved restrictions and clarifications only.
- Use Conventional Commits format for every commit.
- Do not add module-name prefixes to types; rely on the module namespace.
- Keep every approach Simple, Easy to change, Don't Repeat Yourself, and Single Concern.
- Use protocol-oriented programming throughout: depend on protocols and inject concrete implementations.
- iOS 27.1+ with full iPhone Duo support; no older-iOS compatibility paths.
- Swift 6 with the latest compiler, SDK APIs, Apple guidance, and supported upcoming language features. No deprecated approaches.
- Pure Swift and Apple frameworks; avoid third-party dependencies where reasonable.
- Follow the Swift Concurrency plugin's `swift-concurrency` skill.
- Follow [references/testing.md](references/testing.md) when writing or reviewing tests.
- Solana V1 transactions only.
- Separate frameworks by concern; all Helius communication belongs in the RPC/API framework.
- The RPC module exposes a provider-neutral protocol; Helius is a concrete implementation.
- Helius is the only live Solana RPC provider; no app-owned backend/proxy.
- Agree on architecture before implementation; work on one concern at a time.
- Request documentation as Markdown by appending `.md`. Apple API docs: `https://developer.apple.com/documentation/<path>.md`; tutorials/design guidance: `https://developer.apple.com/tutorials/data/<path>.md`.

Keep [references/](references/) concise and free of unapproved designs.
