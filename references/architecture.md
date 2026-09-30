# Architecture

The wallet app owns workflow coordination through internal, protocol-based services. Construct shared services in app composition and presentation coordinators within each window's feature lifetime; callers use the workflow they need without assembling every helper. Views present state and capture approval. Follow the [UI architecture](ui.md) for navigation, window ownership, and themes.

| Component | Responsibility |
| --- | --- |
| RPC | Provider-neutral RPC, DAS, pricing, and confirmed account subscriptions. |
| Transactions | Composable instructions, generic V1 compilation, decoding, validation, and signature assembly. |
| Wallet | Local recovery phrases, account derivation, and cryptographic signing. |
| Vault | Protected recovery storage and authentication for access. |
| Portfolio | Portfolio snapshots, caching, refresh, and reconciliation of confirmed changes. |
| Encoding | Shared codecs. |
| Themes (planned) | Theme-pack models, package reading/writing, validation, and resolution against app-provided defaults. See the [framework contract](../Themes/README.md). |
| Internal app services/coordinators | Own portfolio presentation lifetimes and compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: callers compose instructions, review `Simulation`, then explicitly confirm. Import adapters decode external representations; services own serialization and RPC details.
- Export only cross-module contracts and values; helpers and protocols used only within a module remain internal or private. Protocol-oriented design doesn't require public visibility.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Locally composed instructions and imported V1 transactions share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

[TransactionCoordinator](../widgets/Transactions/Coordination/TransactionCoordinator.swift) is the app's internal entry point for simulation and explicit confirmation, with independent signing for external integrations, backed by injected protocols and focused helpers under `widgets/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; transaction work retains `@concurrent` execution. Reusable encoding and signature assembly belong in Transactions.

[PortfolioCoordinator](../widgets/Portfolio/PortfolioCoordinator.swift) owns one portfolio presentation through `PortfolioCoordinating`. Its observable state is main-actor isolated; it injects `PortfolioProviding` for one configured network. Each window owns its coordinator and supplies its selected wallet and scene activity to the view task; cancellation stops that presentation's observation and manual refreshes. Windows using the same service configuration share the underlying provider. Wallet changes clear the preceding wallet's display state; backgrounding retains its latest snapshot. Create a new coordinator when changing networks. Screen composition remains separate.

Program helpers produce `Instruction` values; adding an operation must not introduce another preparation/signing/submission pipeline. The compiler merges account roles and supports distinct fee payers and multiple authorities. Token prerequisites resolve in an internal feature helper before generic preparation. `TransactionDecoder` and `TransactionBuilder` preserve imported bytes and signature slots; see [usage](transaction-workflow.md). Durable nonces and program-aware explanations remain pending.

## Framework milestones

The agreed wallet, transaction, and portfolio framework milestones are complete. The Themes framework is the next UI foundation; its contract is documented, while its target and implementation remain pending. The deferred capabilities below remain separate milestones.

| Framework | Status |
| --- | --- |
| Encoding | Complete for the current scope. |
| RPC | Complete for the agreed transaction, discovery, DAS, pricing, and confirmed account-subscription workflows. The priority-fee provider limitation remains documented in [RPC scope](rpc-scope.md#provider-limitations). |
| Transactions | Further capabilities are parked; current SOL and supported-token flows remain available. The goal is all Token-2022 extensions, reviewed and agreed individually before implementation. |
| Wallet | Complete for local derivation and SOL-only discovery across twenty addresses in two path families, with one RPC lookup per scan; verified on devnet. See [Wallet](wallet.md). |
| Vault | Implemented and tested, including real simulator Keychain checks. Keep the specific device-validation caveat in [Wallet](wallet.md) separate from framework test status. |
| Portfolio | Complete for native SOL and fungible tokens: rich metadata, native SOL image resolution, independently refreshed prices, paced price requests, separate five-minute freshness checks, explicit reloads, and confirmed-change observation with bounded indexer reconciliation. NFTs, currency conversion, and behavior without DAS remain deferred; see [Portfolio](portfolio.md). |
