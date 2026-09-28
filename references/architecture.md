# Architecture

The wallet app owns workflow coordination through internal, protocol-based services. Create and inject them once; callers use the workflow they need without assembling every helper. Views present state and capture approval.

| Component | Responsibility |
| --- | --- |
| RPC | Provider-neutral RPC/DAS communication and responses. |
| Transactions | Reusable V1 construction, decoding, validation, and signature assembly. |
| Wallet | Local recovery phrases, account derivation, and cryptographic signing. |
| Vault | Protected recovery storage and authentication for access. |
| Portfolio | Portfolio snapshots, caching, and refresh. |
| Encoding | Shared codecs. |
| Internal app services/coordinators | Compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: app workflows exchange typed intents, preparations, signed results, and receipts. Import adapters decode external representations; services own serialization and RPC details.
- Export only cross-module contracts and values; helpers and protocols used only within a module remain internal or private. Protocol-oriented design doesn't require public visibility.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Native SOL construction and externally supplied V1 transactions should share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

Implemented: [TransactionCoordinator](../widgets/Transactions/Coordination/TransactionCoordinator.swift) is the app's internal entry point for preparation and signing, backed by injected protocols and focused helpers under `widgets/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; preparation/signing work retains `@concurrent` execution. The Transfers framework was removed; reusable encoding and signature assembly remain in Transactions.

`TransactionDecoder` inspects complete V1 envelopes; `TransactionBuilder` verifies existing signatures and fills a selected empty signer slot. The app prepares and signs native SOL transfers and imported V1 transactions with recent blockhashes through one typed workflow; see [usage](transfers.md). Durable nonces, program-aware instruction explanations, submission, and confirmation coordination remain pending.
