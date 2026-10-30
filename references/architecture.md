# Architecture

Xcode mirrors the folder layout in [AGENTS.md](../AGENTS.md); target and module names are independent of the folder names. App tests of framework clients also use the shared helpers in `Frameworks/TestSupport`.

The wallet app owns workflow coordination through internal, protocol-based services. Construct shared services and stores in app composition, and coordinators and workflow models in the scene that uses them; callers use the workflow they need without assembling every helper. Views present state and capture approval. Follow the [UI architecture](ui.md) for navigation, window ownership, and themes.

| Component | Responsibility |
| --- | --- |
| [RPC](../Frameworks/RPC/README.md) | Provider-neutral RPC, DAS, pricing, finalized account subscriptions, and signature watches. |
| [Transactions](../Frameworks/Transactions/README.md) | Composable instructions, generic V1 compilation, decoding, validation, and signature assembly. |
| [Wallet](../Frameworks/Wallet/README.md) | Local recovery phrases, account derivation, cryptographic signing, and Solana Rings private-balance keys. |
| [Vault](../Frameworks/Vault/README.md) | Protected recovery storage and authentication for access. |
| [Portfolio](../Frameworks/Portfolio/README.md) | Each account's manual token list, with its balances, prices, refresh, and finalized changes. |
| [Encoding](../Frameworks/Encoding/README.md) | Shared codecs. |
| [Storage](../Frameworks/Storage/README.md) | Device-only values saved as one file or Keychain item each, behind one storage protocol. |
| [ModularArithmetic](../Frameworks/ModularArithmetic/README.md) | Prime-field arithmetic in Montgomery form for the BN254 scalar and base fields and the P-256 scalar field. |
| [Privacy](../Frameworks/Privacy/README.md) | Solana Rings private balances: Poseidon over BN254, the commitments of default-ring transfers, SOL note encryption, shielded-pool deposit and transact instructions, their proofs, registration status, and note sync; it reads through RPC. |
| [Themes](../Frameworks/Themes/README.md) | Color tokens, package reading/writing, validation, and resolution against app-provided defaults. |
| Internal app services/coordinators | Share each wallet's portfolio across windows, own private-balance keys and note sync, and compose review, explicit approval, authentication, signing, and optional submission/confirmation. |

- Prioritize DX at the call site: callers compose instructions, review `Simulation`, explicitly submit it, then confirm the receipt. Import adapters decode external representations; services own serialization and RPC details.
- Keep signing independent of submission: an external requester may need signed transaction bytes without broadcasting. Locally composed instructions and imported V1 transactions share the review/signing workflow.
- Bind review and signing to the exact message, selected account, and network. Authentication grants wallet access; the app separately obtains transaction approval. Preserve existing signatures and identify instructions whose meaning is unknown; simulation success isn't proof of safety.

App-wide data lives in shared `@MainActor @Observable` stores: `AccountStore`, `ContactStore`, `TransactionStore`, `CurrencyStore`, `ProviderStore`, `PortfolioStore`, and `PrivateBalanceStore`. App composition creates each store once, and it lives for the app's lifetime; it reads nothing until `load()`, and views reach it through `.environment(store)` and `@Environment(Store.self)`. Stores over the Storage framework's `PersistentValue` show a change at once, save changes in order, skip unchanged values, and undo a change that can't be saved. Features derive what they show from stores instead of calling each other: Recents are succeeded payments, and portfolios refresh when a transaction settles or the currency or provider changes. Reset App erases every store through `AppReset`'s `Erasable` list.

Each window keeps only navigation: [WindowModel](../App/Sources/Application/WindowModel.swift) holds its account and wallet selection and derives its destination from `AccountStore`, and scene storage keeps its section and network. Each tab owns its workflow models and coordinators as `@State`, such as `ContactsModel` and `SecurityCoordinator`; the wallet scene owns `AppearanceSettingsModel`, so switching tabs keeps an import going. Tab models take the window's account and network as inputs to each call instead of storing them; a transaction review keeps the account and network it was opened for. Portfolio and Contacts use `.id(...)` on the account and network, so another account or network starts the tab again with new state.

[TransactionStore](../App/Sources/Features/Transactions/Storage/TransactionStore.swift) is the one owner of sending, watching, and history for every transaction kind. It keeps public records per account and network, the latest 200 of each, and watches pending records again when a window becomes active. [TransactionCoordinator](../App/Sources/Features/Transactions/Coordination/TransactionCoordinator.swift) is its per-network engine for simulation, explicit submission, and confirmation, with independent signing for external integrations, backed by injected protocols and focused helpers under `App/Sources/Features/Transactions`. These types explicitly remain nonisolated within the MainActor-default app; transaction work retains `@concurrent` execution. Reusable encoding and signature assembly belong in Transactions.

[PortfolioStore](../App/Sources/Features/Portfolio/Storage/PortfolioStore.swift) keeps each wallet's portfolio on each network, main-actor isolated, over one `PortfolioProviding` and `TokenListProviding` service per network. Windows that show the same wallet on the same network share one [WalletPortfolio](../App/Sources/Features/Portfolio/Storage/WalletPortfolio.swift): one observation, which the first observer starts and the last ends, and reloads that every window receives through it. The Portfolio tab and the Contacts keypad read it for the window's account and network, and token additions and removals change the wallet's list through it. Each window observes its wallet for every tab with [portfolioObservation](../App/Sources/Features/Portfolio/Presentation/PortfolioObservation.swift) while its scene is active and the provider settings are read; another account or network restarts the observation. Backgrounding retains the latest snapshot; Reset App erases every wallet's portfolio.

Program helpers produce `Instruction` values; adding an operation must not introduce another preparation/signing/submission pipeline. The compiler merges account roles and supports distinct fee payers and multiple authorities. Token prerequisites resolve in an internal feature helper before generic preparation. `TransactionDecoder` and `TransactionBuilder` preserve imported bytes and signature slots; see [usage](transaction-workflow.md).

## Limitations

Each topic owns its pending and deferred scope: [RPC scope](rpc-scope.md) (QuickNode), [Portfolio](portfolio.md) (NFTs), [Transactions](transactions.md) (durable nonces, Token-2022 extensions), [simulation explanations](transaction-simulation.md), [theme packs](ui.md#theme-packs) (typography and component tokens), and [Privacy](../Frameworks/Privacy/README.md) (token notes, policy rings).
