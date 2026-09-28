# Project constraints

- Keep this file lean: user-approved restrictions and clarifications only.
- Keep skills machine-independent: discover local devices and paths instead of hardcoding them.
- Use Conventional Commits format for every commit.
- Commit or explicitly discard each milestone before starting the next; keep completed milestones in separate commits.
- Do not add module-name prefixes to types; rely on the module namespace.
- Keep project files grouped by concern in real folders that Xcode mirrors; group related tests accordingly.
- Prioritize simplicity, readability, and ease of extension throughout the app and tests; follow Don't Repeat Yourself and Single Concern.
- Prioritize developer experience: express intent with typed APIs and encapsulate serialization and transport details inside services.
- Use protocol-oriented programming throughout: depend on protocols and inject concrete implementations.
- Compose wallet workflows in internal app services/coordinators, outside views; keep frameworks focused on reusable concerns. Follow [references/architecture.md](references/architecture.md).
- Expose only contracts and values needed across module boundaries; keep implementation helpers internal or private.
- iOS 27.1+ with full iPhone Duo support; no older-iOS compatibility paths.
- Swift 6 with the latest compiler, SDK APIs, Apple guidance, and supported upcoming language features. No deprecated approaches.
- Pure Swift and Apple frameworks; avoid third-party dependencies where reasonable.
- Use `'/Applications/SF Symbols.app/Contents/Executables/sfsymbols'` when interacting with SF Symbols.
- Follow the Swift Concurrency plugin's `swift-concurrency` skill.
- Follow [references/testing.md](references/testing.md) when writing or reviewing tests.
- Verify RPC integrations with real clients on devnet; do not add fake RPC implementations for tests.
- Never request funding for a wallet without verified, retained recovery. Reuse controlled devnet test wallets and return test funds after fees; never discard funded wallet recovery.
- Document every function and initializer using Apple DocC conventions.
- Solana V1 transactions only; compose ordered instructions through one shared transaction pipeline. Transfers are instruction helpers, not a separate transaction model.
- Support SPL Token and Token-2022 together through shared token-transfer APIs.
- Separate frameworks by concern; all Solana RPC and DAS communication belongs in the RPC/API framework.
- Keep RPC and DAS contracts provider-neutral; Helius is the current implementation, and providers must be interchangeable behind protocols.
- Surface RPC rate-limit errors to consumers; do not add automatic throttling or retries in RPC.
- Add RPC methods only for concrete needs of agreed wallet features; follow [references/rpc-scope.md](references/rpc-scope.md), not endpoint coverage.
- Keep the app decentralized: no app-owned backend or proxy. Connect directly to Solana RPC providers.
- Use one submission strategy: `none` sends identical signed bytes concurrently through configured same-network ordinary RPCs; `standard` and `premium` use Sender exclusively. Follow [references/transaction-workflow.md](references/transaction-workflow.md).
- Use the selected provider's DAS interface only for portfolio viewing; keep DAS out of transaction submission contracts, validation, and routing. Follow [references/portfolio.md](references/portfolio.md).
- Keep wallet recovery material device-only, excluded from iCloud sync and backups; follow [references/wallet.md](references/wallet.md).
- Agree on architecture before implementation; work on one concern at a time.
- Request documentation as Markdown by appending `.md`. Apple API docs: `https://developer.apple.com/documentation/<path>.md`; tutorials/design guidance: `https://developer.apple.com/tutorials/data/<path>.md`.

Keep [references/](references/) concise and free of unapproved designs.
