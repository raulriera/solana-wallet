# Project constraints

Keep this file lean: user-approved restrictions and clarifications only.

## Non-negotiable

Stop and ask the user before you break one of these.

- Prioritize simplicity, readability, and ease of extension throughout the app and tests; follow Don't Repeat Yourself and Single Concern. Before you write a second copy of a code shape, extract it into one generic, non-product helper, such as an extension, operator, or small type; a ban on product-specific helpers never covers generic ones.
- **Hard rule:** Never extract UI into view-returning computed properties or helper functions, including `@ViewBuilder` helpers. Every extracted view/component must be an independent `View` type in its own Swift file. Protocol-required rendering entry points and thin modifier/style convenience APIs are exempt; other helpers may return data or perform actions, not compose views.
- Use SwiftUI. Ask the user before using UIKit, even for a probe; propose it only when required functionality cannot be achieved with SwiftUI or a concrete performance need justifies it.
- Give small views, such as rows, buttons, and menus, plain values and projected bindings, never the models they change. For actions, pass an action value, a struct with `callAsFunction`, and read shared ones from the environment, as SwiftUI does with `dismiss`. Never store a closure as a custom view's input; SwiftUI can't compare closures.
- Name error types and properties `Error`/`error`, never `Failure`/`failure`. Never store, pass, or show errors as strings, including another error's `localizedDescription`. User-facing errors are payload-free enums conforming to `LocalizedError`, with the title in `errorDescription` and the message in `recoverySuggestion`; present them with `alert(error:)`.
- Document production code only, with Apple DocC conventions: a summary of what each function, initializer, and type does, and its parameters, return value, and thrown errors. Document properties and cases only when their names are not enough. Write no other comments: no inline comments, no comments in tests, and never history, sources, versions, rationale, or what other code does.
- Keep the license header of code copied from open-source projects; it is the only comment allowed besides DocC.
- Treat `main` as sacred: change it only when the user asks, and never rewrite its history.
- Never create merge commits anywhere: update a branch by rebasing it onto `origin/main`, and land work on `main` by rebase or squash, including PR merges.
- Never drop saved wallets during launch, app updates, or validation. Preserve stored metadata and recovery; treat loading errors as failures, not an empty wallet.
- Verify live integrations with real RPC clients: mainnet for read-only behavior, devnet for tests that fund wallets, submit transactions, or incur fees. Keep mainnet-only delivery tests explicitly opt-in with approved spending limits. Do not add fake RPC implementations for tests.

## Process

- Agree on architecture before implementation; work on one concern at a time.
- Resolve unapproved UI design and behavior with the user before implementing it; do not infer production approval from disposable mockups. Follow [references/ui.md](references/ui.md).
- Keep milestones small: one concern and a diff that can be reviewed in one sitting, at most 8 files, not counting Markdown files. Renames and mechanical edits count; only one-line import additions do not. List the files before writing code, and split larger work into more milestones; sweeps and side fixes are milestones of their own.
- Build a feature's milestones on one branch off `main`. Leave each milestone uncommitted until the user reviews it, then commit it as its own commit before starting the next. When the feature is done, a PR rebases and squashes it into `main`.

## Git

- Never lose work: land committed work where the user wants it before deleting or archiving its branch or worktree.
- Use Conventional Commits format for every commit, and name branches `<type>/<topic>` with a Conventional Commits type, such as `refactor/provider-wording`; never use agent prefixes like `claude/`. Rename a wrongly named branch to a correct name.
- Author commits with the user's git identity, never an agent identity. Add no AI attribution lines to commits or PR descriptions.
- Ask before opening PRs, keep their titles short, and follow the template: one small paragraph summarizing the change, not a list of every detail, and one concise line per verification step.

## Platform and tools

- iOS 27.1+ with full iPhone Duo support; no older-iOS compatibility paths.
- Swift 6 with the latest compiler, SDK APIs, Apple guidance, and supported upcoming language features. No deprecated approaches.
- Pure Swift and Apple frameworks; avoid third-party dependencies where reasonable.
- Use only three simulators for development and verification: one regular iPhone, one iPad, and one iPhone Duo. Test resizing in Device Hub's resize mode on the regular iPhone. Reuse existing devices; do not create simulators or expand this matrix without explicit user approval.
- Keep skills machine-independent: discover local devices and paths instead of hardcoding them.
- Use `'/Applications/SF Symbols.app/Contents/Executables/sfsymbols'` when interacting with SF Symbols.
- Request documentation as Markdown by appending `.md`. Apple API docs: `https://developer.apple.com/documentation/<path>.md`; tutorials/design guidance: `https://developer.apple.com/tutorials/data/<path>.md`.

## Skills

- Use [SwiftUI Expert](plugin://swiftui-expert@swiftui-expert-skill) and Xcode's `swiftui-specialist` skill for UI work.
- Validate concurrency changes against current Apple documentation and the Swift Concurrency plugin's `swift-concurrency` skill.
- Use Xcode's skills for their concerns, alongside the plugins named here. `xcrun agent skills export` installs most of them; the accessibility and translation skills come only from Xcode's agent plugin (`xcrun agent plugin path --plugin-format <agent>`). Skills that call Xcode's tools need its MCP bridge (`xcrun mcpbridge`).
  - `swiftui-whats-new-27`: SwiftUI code.
  - `app-resizability`: layout, resizing, and iPhone Duo reviews.
  - `device-interaction`: simulator verification.
  - `accessibility-dynamic-type-specialist`, `accessibility-voiceover-specialist`, and `accessibility-sufficient-contrast-specialist`: accessibility audits.
  - `app-intents-specialist` and `app-intents-whats-new-27`: App Intents.
  - `modernize-tests`, with `swift-testing-expert`: every test change, before review.
  - `xctrace`: Instruments profiling and trace analysis.
  - `translation` and `translation-coordinator`: String Catalogs.
  - `audit-xcode-security-settings`: build settings.
  - `building-document-based-swiftui-applications`: file packages and document types, such as theme packs.
  - `adopt-c-bounds-safety`: C code.
- Use the `solana-dev` skill for Solana protocol facts, and read the reference for the concern before you write or review Solana code. `npx skills add solana-foundation/solana-dev-skill` installs it. Take on-chain facts only: program IDs, account layouts, instruction rules, and limits. Its JavaScript, Rust, and test tooling is not for this app, and this file wins where they differ. Do not add the MCP server it names.
  - `tokens.md`, with `kit/programs/token.md` and `kit/programs/token-2022.md`: mints, token accounts, associated token accounts, and Token-2022 extensions.
  - `transactions-v1.md`, with `kit/programs/compute-budget.md` and `concepts.md`: the V1 wire format, resource limits, and priority fees.
  - `kit/programs/system.md`: SOL transfers and account creation.
  - `security.md`: the client-side checklist and the Token-2022 sections.
  - `rpc-quick-lookups.md`: one-off chain reads during an investigation.
  - `common-errors.md`: V1 transaction errors.

## Project layout

- Group files by concern in real folders that Xcode mirrors.
- `Frameworks/<Module>` holds `Sources`, `Tests`, and a concise, factual `README.md` for third-party readers, without project history, progress reports, or agent-only guidance. `Frameworks/TestSupport` holds test helpers shared by frameworks.
- `App/Sources`:
  - `Application`: app entry and window ownership. `Composition` assembles services and coordinators, `Routing` holds destination contracts and navigation state, and `Startup` restores launch state.
  - `Features/<Feature>`: workflows, coordinators, contracts, and models. Add focused folders only as needed, such as scenes for navigation containers, screens for destinations, sections, components, routing, and styles; they stay with their feature unless shared.
  - `Appearance`: the shared catalog, preferences, coordination, storage, recovery, and per-window rendering. Editing UI and workflows go in `Features/AppearanceSettings`.
  - `UI`: UI and layout used across features. `Components`, `Modifiers`, and `Styles` group shared views, view modifiers, and styles by kind. `Environment` declares every custom environment value, one file each; the value's type stays with its owner.
  - `Extensions`: shared extensions of system types, one file per type and concern, such as `Decimal+Rounding.swift`. An extension of a system type is private to its file or lives here, except fluent conveniences that stay with their modifier or style; search here before writing one.
  - `Resources`: shipped assets, settings bundles, built-in themes, and the privacy manifest.
  - `Configuration`: Info.plist and entitlements.
- `App/Tests` mirrors that ownership under `Application`, `Features`, `Appearance`, and `Extensions`. `UI` holds UI tests, grouped by feature, and `Integration/<Framework>` holds app-hosted framework integration checks. Feature-specific fixtures stay with their tests; helpers used across app concerns go in `TestSupport`, grouped by responsibility and actual consumers.

## Architecture

- Separate frameworks by concern and keep them focused on reusable concerns. Compose wallet workflows in internal app services/coordinators, outside views. Follow [references/architecture.md](references/architecture.md).
- Expose only contracts and values needed across module boundaries; keep implementation helpers, and protocols used only within a module, internal or private.
- Use protocol-oriented programming where a role has more than one implementation, or where tests replace it: depend on the protocol and inject the implementation. Use the concrete type for a role with one implementation, and add the protocol together with the second.
- Name each workflow model `<Task>Model` and keep it in its feature's `Models` folder. Workflow models hold facts only, without SwiftUI or Accessibility code: input, running attempts, typed rejections and errors, and completion as observable state, such as `isSaved`. Never give them closures that capture view state. Views own animation, haptics, and VoiceOver announcements. Presented views close themselves with `dismiss`; other owners react with `onChange`.
- Keep root views focused on window/scene ownership and feature composition. Extract a presentation lifecycle into a focused modifier with a fluent helper only when it has its own state or several steps; otherwise apply `task` and `alert(error:)` where the view is composed.
- Support simultaneous wallet windows where the system allows them; keep each window's wallet selection, navigation, and presented tasks independent.
- Own appearance loading and resolved palettes at each window's root. Inject the palette and tint there; feature scenes and screens inherit appearance through the environment instead of receiving or loading it separately. Share appearance services across windows, not their rendered state.

## Code

- Prioritize developer experience: express intent with typed APIs and encapsulate serialization and transport details inside services.
- Learn how Apple solves a problem and mirror its API shape and naming before inventing your own: extend the Apple type as Apple would, such as `URL.persistentDirectory` beside `URL.cachesDirectory`, instead of adding a wrapper type.
- Do not add module-name prefixes to types; rely on the module namespace.
- Name each implementation of a role with that role as its suffix, such as `JupiterPriceProvider` and `CustomPriceProvider`, as Apple does with `JSONDecoder` and `PropertyListDecoder`.
- Don't restate what's already evident: no labels or accessibility labels that repeat visible text, a control's role, or the enclosing screen's title; no view types that only wrap a system view; no tests that assert a value equals its own declaration.

## SwiftUI

- Customize a control's appearance with its SwiftUI style protocol, such as `LabelStyle`, `ButtonStyle`, or `FormStyle`, before adding a view type or modifier.
- When creating custom view modifiers, styles, or similar SwiftUI APIs, provide and use a fluent convenience helper, such as a `View` extension for a modifier or a static member for a style. Keep it with the underlying type and delegate directly to that type without duplicating behavior or branching the view hierarchy.

## UI

- Follow [UI architecture](references/ui.md) for tab bar and adaptive `NavigationSplitView` navigation, with the approved onboarding `NavigationStack` exception, `ArrangementView` wherever a screen has two peer regions, theme packs, and HIG requirements for app-owned UI and built-in themes; do not gate user-created packs on HIG aesthetics.
- Put a `Form` screen's actions in its last section as button rows, as iOS Settings does: `primary` text, or the `destructive` `warning` label with a trash symbol for destructive actions. A content-unavailable screen puts its one action in `ContentUnavailableView`'s actions. On input screens, put the committing action at the trailing edge of the top toolbar instead, as a prominent symbol-only confirm button.
- Use the system's content margins for `Form`, `List`, and `ScrollView`. In wide containers, limit content to the shared 896 pt readable width, as Settings does on iPad; add no other custom margins.
- Inset bars and other window-edge-aligned views with `contentMargins(for: .container)`, never fixed horizontal padding, and read the guide from `GeometryProxy` instead of hardcoding margin values.
- Keep interaction feedback visually stable; do not flash progress rows, spinners, or disabled states for quick actions, including preference changes and theme package operations.
- Treat motion as part of the UI: use native animations for meaningful state changes, including row insertion and removal. Add explicit `accessibilityReduceMotion` checks only for pronounced animations identified by the user, not every animation.

## Testing

- Follow [references/testing.md](references/testing.md) when writing or reviewing tests.
- Name test functions with sentence-style raw identifiers instead of camelCase; do not duplicate those names in `@Test` display strings.
- Devnet tests that move funds use the test wallet seed from ignored local configuration, never create wallets, and leave transferred funds with the recipient.

## Solana

- Solana V1 transactions only; compose ordered instructions through one shared transaction pipeline. Transfers are instruction helpers, not a separate transaction model.
- Support SPL Token and Token-2022 together through shared token-transfer APIs. Review and agree on each Token-2022 extension with the user before implementing it.
- On V1 transactions, set resource limits and the priority fee in the message configuration; never add Compute Budget instructions.
- Read a mint's token program from the mint account's owner, and use it for every instruction and associated token account of that mint. Check an account's owner before decoding it.
- Move tokens with `TransferChecked`. Read the decimals from the mint; write them as a number only where the code declares a token by hand, such as a list of supported tokens.
- An asset is a required, explicit input: no default argument, no fallback, and no optional where `nil` means SOL, in tests and fixtures too.
- Model tokens with Solana's types and names: `Mint`, `Token` (a token account), and `TokenAmount`. Add no parallel type for a token fact, and never pass decimals beside an asset.
- Create an associated token account with `CreateIdempotent`.
- Use one submission strategy: `none` sends through the selected provider; `standard` and `premium` use Sender with its tip. Send each transaction through one RPC only. Follow [references/transaction-workflow.md](references/transaction-workflow.md).

## RPC and providers

- Keep the app decentralized: no app-owned backend or proxy. Connect directly to Solana RPC providers.
- All Solana RPC, DAS, and price communication belongs in the RPC/API framework.
- Keep RPC, DAS, and pricing contracts provider-neutral. Public Solana RPC, Helius, and Jupiter are implementations; providers must be interchangeable behind protocols and transform responses into shared types.
- Offer two built-in providers: public Solana RPC (no key) and Helius. People can also add custom HTTPS RPC URLs that serve standard requests, account subscriptions, and signature and root subscriptions. Each supports every standard wallet feature. Optional capabilities, such as CDN logos and private balances, are protocols: a provider has one when it conforms, and the app hides a feature that the selected provider lacks.
- Never ship provider API keys in the app bundle or source; users enter them in the app. Ignored local configuration supplies keys to tests only.
- Add RPC methods only for concrete needs of agreed wallet features; follow [references/rpc-scope.md](references/rpc-scope.md), not endpoint coverage.
- Surface rate-limit errors to consumers; do not automatically retry. Pace price-provider batches within their request budgets; do not throttle Solana RPC or DAS requests.

## Wallet and storage

- Keep wallet recovery material device-only, excluded from iCloud sync and backups; follow [references/wallet.md](references/wallet.md).
- Discover accounts with one SOL-only lookup for twenty addresses; intentionally ignore zero-SOL accounts.
- Show a manual token list for each account; read its balances with standard RPC and use DAS only to look up logos on the selected provider's CDN, loaded over HTTPS. Never request creator-hosted or off-chain artwork URLs, which expose the user's IP address. Follow [references/portfolio.md](references/portfolio.md).
- Save files the person would lose under `URL.persistentDirectory`, which only Reset App deletes, and files the app can create again, such as balances, under `URL.ephemeralDirectory`. Give each store its own subfolder; Reset deletes both directories, so a new store needs no reset change.

## References

Keep [references/](references/) to primitives the code can't show: approved rules, boundaries, and invariants that guide new work. Do not add feature specs, screen behavior, API walkthroughs, research, to-dos, project history, or test results; the code, DocC, and framework READMEs cover those. Keep unapproved designs out.
