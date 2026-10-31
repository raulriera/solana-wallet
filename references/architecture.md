# Architecture

Xcode mirrors the folder layout in [AGENTS.md](../AGENTS.md); target and module names are independent of the folder names. Follow the [UI architecture](ui.md) for navigation, windows, and themes.

| Component | Responsibility |
| --- | --- |
| [RPC](../Frameworks/RPC/README.md) | Provider-neutral RPC, DAS, pricing, exchange rates, and subscriptions. |
| [Transactions](../Frameworks/Transactions/README.md) | Composable instructions, V1 compilation, decoding, validation, and signature assembly. |
| [Wallet](../Frameworks/Wallet/README.md) | Local recovery phrases, account derivation, signing, and private-balance keys. |
| [Vault](../Frameworks/Vault/README.md) | Protected recovery storage and authenticated access. |
| [Portfolio](../Frameworks/Portfolio/README.md) | Each account's manual token list, balances, prices, and finalized changes. |
| [Encoding](../Frameworks/Encoding/README.md) | Shared codecs. |
| [Storage](../Frameworks/Storage/README.md) | Device-only values saved as one file or Keychain item each. |
| [ModularArithmetic](../Frameworks/ModularArithmetic/README.md) | Prime-field arithmetic for BN254 and P-256. |
| [Privacy](../Frameworks/Privacy/README.md) | Solana Rings private balances; it reads through RPC. |
| [Themes](../Frameworks/Themes/README.md) | Theme packages, validation, and resolution against app defaults. |
| App services and coordinators | Shared stores and every workflow: review, approval, authentication, signing, submission, and confirmation. |

- App composition creates shared services and `@MainActor @Observable` stores once, for the app's lifetime; views read stores from the environment. Scenes create the coordinators and workflow models they use. Views present state and capture approval.
- Features derive what they show from stores instead of calling each other. Every store that saves data joins `AppReset`'s `Erasable` list.
- A window keeps only navigation. Tabs own their workflow models as `@State` and pass the window's account and network into each call instead of storing them.
- Keep signing independent of submission: an external requester may need signed bytes without a broadcast.
- Bind review and signing to the exact message, account, and network. Authentication grants wallet access; approval is separate. Simulation success isn't proof of safety.
- Program helpers produce `Instruction` values. Every operation goes through the one [transaction workflow](transaction-workflow.md); never add another preparation, signing, or submission pipeline. A composition stays atomic: nothing splits automatically. Durable nonces aren't supported.
- The app sets `MERGED_BINARY_TYPE = automatic` in `Configuration/App.xcconfig`. Every framework is a direct app dependency in Link Binary With Libraries; keep the merging setting on the app only.
