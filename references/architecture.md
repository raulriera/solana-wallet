# Architecture

The wallet app owns workflow coordination through internal, protocol-based services. Create and inject them once; callers use the workflow they need without assembling every helper. Views present state and capture approval.

| Component | Responsibility |
| --- | --- |
| RPC | Provider-neutral RPC/DAS communication and responses. |
| Transactions | Composable instructions, generic V1 compilation, decoding, validation, and signature assembly. |
| Wallet | Local recovery phrases, account derivation, and cryptographic signing. |
| Vault | Protected recovery storage and authentication for access. |
| Portfolio | Portfolio snapshots, caching, and refresh. |
| Encoding | Shared codecs. |
| Internal app services/coordinators | Compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: callers compose instructions, review `Simulation`, then explicitly confirm. Import adapters decode external representations; services own serialization and RPC details.
- Export only cross-module contracts and values; helpers and protocols used only within a module remain internal or private. Protocol-oriented design doesn't require public visibility.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Locally composed instructions and imported V1 transactions share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

[TransactionCoordinator](../widgets/Transactions/Coordination/TransactionCoordinator.swift) is the app's internal entry point for simulation and explicit confirmation, with independent signing for external integrations, backed by injected protocols and focused helpers under `widgets/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; transaction work retains `@concurrent` execution. Reusable encoding and signature assembly belong in Transactions.

Program helpers produce `Instruction` values; adding an operation must not introduce another preparation/signing/submission pipeline. The compiler merges account roles and supports distinct fee payers and multiple authorities. Token prerequisites resolve in an internal feature helper before generic preparation. `TransactionDecoder` and `TransactionBuilder` preserve imported bytes and signature slots; see [usage](transaction-workflow.md). Durable nonces and program-aware explanations remain pending.

## Framework milestones

Complete framework work before App/UI work.

| Framework | Status |
| --- | --- |
| Encoding | Complete for the current scope. |
| RPC | Devnet transaction and account-discovery workflows verified. A priority-fee provider limitation remains documented in [RPC scope](rpc-scope.md#provider-limitations). |
| Transactions | Further capabilities are parked; current SOL and supported-token flows remain available. The goal is all Token-2022 extensions, reviewed and agreed individually before implementation. |
| Wallet | Complete for local derivation and SOL-only discovery across twenty addresses in two path families, with one RPC lookup per scan; verified on devnet. See [Wallet](wallet.md). |
| Vault | Implemented and tested, including real simulator Keychain checks. Keep the specific device-validation caveat in [Wallet](wallet.md) separate from framework test status. |
| Portfolio | Complete for the agreed DAS holdings, persistent cache, and refresh scope. Currency conversion and behavior without DAS remain deferred; see [Portfolio](portfolio.md). |
