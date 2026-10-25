# Architecture

Xcode mirrors the folder layout in [AGENTS.md](../AGENTS.md); target and module names are independent of the folder names. App tests of framework clients also use the shared helpers in `Frameworks/TestSupport`.

The wallet app owns workflow coordination through internal, protocol-based services. Construct shared services in app composition and presentation coordinators within each window's feature lifetime; callers use the workflow they need without assembling every helper. Views present state and capture approval. Follow the [UI architecture](ui.md) for navigation, window ownership, and themes.

| Component | Responsibility |
| --- | --- |
| [RPC](../Frameworks/RPC/README.md) | Provider-neutral RPC, DAS, pricing, finalized account subscriptions, and signature watches. |
| [Transactions](../Frameworks/Transactions/README.md) | Composable instructions, generic V1 compilation, decoding, validation, and signature assembly. |
| [Wallet](../Frameworks/Wallet/README.md) | Local recovery phrases, account derivation, cryptographic signing, and Solana Rings private-balance keys. |
| [Vault](../Frameworks/Vault/README.md) | Protected recovery storage and authentication for access. |
| [Portfolio](../Frameworks/Portfolio/README.md) | Each account's manual token list, with its balances, prices, refresh, and finalized changes. |
| [Encoding](../Frameworks/Encoding/README.md) | Shared codecs. |
| [ModularArithmetic](../Frameworks/ModularArithmetic/README.md) | Prime-field arithmetic in Montgomery form for the BN254 scalar and base fields and the P-256 scalar field. |
| [Privacy](../Frameworks/Privacy/README.md) | Solana Rings private balances: Poseidon over BN254, the commitments of default-ring transfers, SOL note encryption, shielded-pool deposit and transact instructions, their proofs, registration status, and note sync; it reads through RPC. |
| [Themes](../Frameworks/Themes/README.md) | Color tokens, package reading/writing, validation, and resolution against app-provided defaults. |
| Internal app services/coordinators | Own portfolio presentation lifetimes, private-balance keys and note sync, and compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: callers compose instructions, review `Simulation`, explicitly submit it, then confirm the receipt. Import adapters decode external representations; services own serialization and RPC details.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Locally composed instructions and imported V1 transactions share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

[TransactionCoordinator](../App/Sources/Features/Transactions/Coordination/TransactionCoordinator.swift) is the app's internal entry point for simulation, explicit submission, and confirmation, with independent signing for external integrations, backed by injected protocols and focused helpers under `App/Sources/Features/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; transaction work retains `@concurrent` execution. Reusable encoding and signature assembly belong in Transactions.

[PortfolioCoordinator](../App/Sources/Features/Portfolio/Coordination/PortfolioCoordinator.swift) owns one portfolio presentation through `PortfolioCoordinating`. Its observable state is main-actor isolated; it injects `PortfolioProviding` and `TokenListProviding` for one configured network and adds and removes tokens in its wallet's list. Each window owns its coordinator and supplies its selected wallet and scene activity to the view task; cancellation stops that presentation's observation and manual refreshes. Windows using the same service configuration share the underlying provider. Wallet changes clear the preceding wallet's display state; backgrounding retains its latest snapshot. Create a new coordinator when changing networks. Screen composition remains separate.

Program helpers produce `Instruction` values; adding an operation must not introduce another preparation/signing/submission pipeline. The compiler merges account roles and supports distinct fee payers and multiple authorities. Token prerequisites resolve in an internal feature helper before generic preparation. `TransactionDecoder` and `TransactionBuilder` preserve imported bytes and signature slots; see [usage](transaction-workflow.md).

## Limitations

- Public Solana RPC and Helius are the built-in providers; QuickNode is planned as the third. See [RPC scope](rpc-scope.md).
- Portfolios show native SOL and fungible tokens only; NFTs and currency conversion are deferred. See [Portfolio](portfolio.md).
- Durable nonces and program-aware transaction explanations are pending; see [simulation explanations](transaction-simulation.md).
- Token-2022 extensions are added one at a time, each agreed with the user first; unsupported extensions fail explicitly. See [Transactions](transactions.md).
- Theme packs support color tokens and bundled images; typography and other component tokens are deferred. See [UI architecture](ui.md#theme-packs).
- Private balances support SOL notes in the default ring; token notes and policy rings aren't supported. See [Privacy](../Frameworks/Privacy/README.md).
