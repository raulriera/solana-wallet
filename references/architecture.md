# Architecture

App source and tests live in `App/Sources` and `App/Tests`. Each framework lives in `Frameworks/<Module>` with `Sources`, `Tests`, and a `README.md`. Xcode mirrors these folders; target and module names are independent of the folder names. Test helpers shared by frameworks, and by app tests of framework clients, live in `Frameworks/TestSupport`.

The wallet app owns workflow coordination through internal, protocol-based services. Construct shared services in app composition and presentation coordinators within each window's feature lifetime; callers use the workflow they need without assembling every helper. Views present state and capture approval. Follow the [UI architecture](ui.md) for navigation, window ownership, and themes.

| Component | Responsibility |
| --- | --- |
| [RPC](../Frameworks/RPC/README.md) | Provider-neutral RPC, DAS, pricing, finalized account subscriptions, and signature watches. |
| [Transactions](../Frameworks/Transactions/README.md) | Composable instructions, generic V1 compilation, decoding, validation, and signature assembly. |
| [Wallet](../Frameworks/Wallet/README.md) | Local recovery phrases, account derivation, cryptographic signing, and Solana Rings private-balance keys. |
| [Vault](../Frameworks/Vault/README.md) | Protected recovery storage and authentication for access. |
| [Portfolio](../Frameworks/Portfolio/README.md) | Each account's manual token list, with its balances, prices, refresh, and finalized changes. |
| [Encoding](../Frameworks/Encoding/README.md) | Shared codecs. |
| [ModularArithmetic](../Frameworks/ModularArithmetic/README.md) | Prime-field arithmetic in Montgomery form for the BN254 and P-256 scalar fields. |
| [Privacy](../Frameworks/Privacy/README.md) | Solana Rings private-balance cryptography: Poseidon over BN254, the commitments of default-ring transfers, and SOL note encryption. |
| [Themes](../Frameworks/Themes/README.md) | Color tokens, package reading/writing, validation, and resolution against app-provided defaults. |
| Internal app services/coordinators | Own portfolio presentation lifetimes and compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: callers compose instructions, review `Simulation`, explicitly submit it, then confirm the receipt. Import adapters decode external representations; services own serialization and RPC details.
- Export only cross-module contracts and values; helpers and protocols used only within a module remain internal or private. Protocol-oriented design doesn't require public visibility.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Locally composed instructions and imported V1 transactions share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

[TransactionCoordinator](../App/Sources/Features/Transactions/Coordination/TransactionCoordinator.swift) is the app's internal entry point for simulation, explicit submission, and confirmation, with independent signing for external integrations, backed by injected protocols and focused helpers under `App/Sources/Features/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; transaction work retains `@concurrent` execution. Reusable encoding and signature assembly belong in Transactions.

[PortfolioCoordinator](../App/Sources/Features/Portfolio/Coordination/PortfolioCoordinator.swift) owns one portfolio presentation through `PortfolioCoordinating`. Its observable state is main-actor isolated; it injects `PortfolioProviding` and `TokenListProviding` for one configured network and adds and removes tokens in its wallet's list. Each window owns its coordinator and supplies its selected wallet and scene activity to the view task; cancellation stops that presentation's observation and manual refreshes. Windows using the same service configuration share the underlying provider. Wallet changes clear the preceding wallet's display state; backgrounding retains its latest snapshot. Create a new coordinator when changing networks. Screen composition remains separate.

Program helpers produce `Instruction` values; adding an operation must not introduce another preparation/signing/submission pipeline. The compiler merges account roles and supports distinct fee payers and multiple authorities. Token prerequisites resolve in an internal feature helper before generic preparation. `TransactionDecoder` and `TransactionBuilder` preserve imported bytes and signature slots; see [usage](transaction-workflow.md). Durable nonces and program-aware explanations remain pending.

## Framework milestones

The agreed wallet, transaction, portfolio, and initial color-only Themes framework milestones are complete. The deferred capabilities below remain separate milestones.

| Framework | Status |
| --- | --- |
| Encoding | Complete for the current scope. |
| ModularArithmetic | Complete for the current scope: the BN254 and P-256 scalar fields. |
| Privacy | Poseidon, the commitments of default-ring transfers between Ed25519 owners, and the encryption of their SOL notes are complete; token notes and instruction helpers are separate milestones. |
| Themes | Color-only package service with app-supplied defaults and PNG/JPEG assets. App services manage immutable built-ins, custom installations, app/wallet preferences, deletion fallbacks, and one-time recovery from iOS Settings. Import/export presentation and rendering remain separate; see [UI architecture](ui.md). |
| RPC | Complete for the agreed transaction, discovery, DAS, pricing, finalized account-subscription, and signature-watch workflows. The manual token list adds a QuickNode client and per-account subscriptions. |
| Transactions | Further capabilities are parked; current SOL and supported-token flows remain available. The goal is all Token-2022 extensions, reviewed and agreed individually before implementation. |
| Wallet | Complete for local derivation and SOL-only discovery across twenty addresses in two path families, with one RPC lookup per scan, verified on devnet; and for Solana Rings private-balance keys. See [Wallet](wallet.md). |
| Vault | Implemented and tested, including real simulator Keychain checks. Keep the specific device-validation caveat in [Wallet](wallet.md) separate from framework test status. |
| Portfolio | Complete for each account's manual token list, read with standard RPC; DAS only looks up logos. NFTs and currency conversion remain deferred; see [Portfolio](portfolio.md). |
