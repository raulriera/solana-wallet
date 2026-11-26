# Project constraints

User-approved restrictions and clarifications only. Keep this file short.

## Non-negotiable

Stop and ask the user before you break one of these.

- Edit only after the user approves a plan, architecture included; a different shape needs a new plan. Work on one concern at a time.
- Commit, amend, reset, push, open a PR, or merge only when the user's current message names that action. Never force push or create merge commits. Change `main` only when the user asks, and never rewrite its history.
- Before a branch's PR, run simplify, code review, the skills below that fit the change, and the Unit test plan on the whole branch, and fix what they find.
- Keep the app and tests simple, readable, and easy to extend, with Don't Repeat Yourself and Single Concern. Before a second copy of a code shape, extract one generic, non-product helper, such as an extension, operator, or small type; a ban on product-specific helpers never covers generic ones. Until the first release, add no backwards compatibility, migrations, or fallbacks for rare faults.
- Network, amount, and asset are explicit inputs: no default argument, fallback, or optional that stands for a default. For the asset, this covers tests and fixtures too.
- Never compose views in computed properties or helper functions, `@ViewBuilder` included; other helpers return data or perform actions. Each extracted view is an independent `View` type in its own file. Protocol-required rendering entry points and fluent modifier and style helpers are exempt.

## Workflow

- A milestone is one concern, reviewable in one sitting: at most 8 non-Markdown files, where renames and mechanical edits count and one-line imports don't. List the files before writing code. Sweeps and side fixes are separate milestones.
- Agree on UI design and behavior with the user before building it; mockups don't approve production. See [references/ui.md](references/ui.md).
- Name branches `<type>/<topic>` with a Conventional Commits type, such as `refactor/provider-wording`, never with an agent prefix such as `claude/`; rename a wrong one. Update branches by rebasing onto `origin/main`.
- Build a feature on one branch off `main`. Leave each milestone uncommitted until the user reviews it, after a build, the Unit test plan, and a check of the diff against the Non-negotiables; after review, it becomes its own commit before the next one starts. Land work on `main` by rebase or squash, PRs included.
- Commits use Conventional Commits and the user's git identity. Commits and PRs carry no AI attribution.
- Ask before opening a PR. Use a short title and the template: one short summary paragraph and one line per verification step.
- Never lose work: before you delete or archive a branch or worktree, land its committed work where the user wants it.

## Platform and tools

- iOS 27.1+ with full iPhone Duo support; no paths for older iOS. Swift 6 with the latest compiler, SDK, Apple guidance, and supported upcoming features; nothing deprecated.
- Pure Swift and Apple frameworks; avoid third-party dependencies where reasonable. Use SwiftUI. Ask before using UIKit, even for a probe, and propose it only when SwiftUI can't do the job or a concrete performance need requires it.
- Use only one regular iPhone, one iPad, and one iPhone Duo simulator, and reuse them. Test resizing in Device Hub's resize mode on the iPhone. Create no simulators without the user's explicit approval.
- Keep skills machine-independent: discover devices and paths, never hardcode them.
- SF Symbols: `'/Applications/SF Symbols.app/Contents/Executables/sfsymbols'`.
- Read documentation as Markdown by appending `.md`: `https://developer.apple.com/documentation/<path>.md`, and `https://developer.apple.com/tutorials/data/<path>.md` for tutorials and design guidance.

## Skills

Use Xcode's skills for their concerns, alongside the ones named here.

- UI and SwiftUI code: [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill), `swiftui-specialist`, and `swiftui-whats-new-27`. Layout, resizing, and iPhone Duo reviews: `app-resizability`. Simulator verification: `device-interaction`.
- Concurrency: validate changes against current Apple documentation and `swift-concurrency`.
- Test changes, before a branch's PR: `modernize-tests` with `swift-testing-expert`.
- Accessibility audits: `accessibility-dynamic-type-specialist`, `accessibility-voiceover-specialist`, and `accessibility-sufficient-contrast-specialist`.
- Others: `app-intents-specialist` and `app-intents-whats-new-27` (App Intents), `xctrace` (profiling and trace analysis), `translation` and `translation-coordinator` (String Catalogs), `audit-xcode-security-settings` (build settings), `building-document-based-swiftui-applications` (file packages and document types, such as theme packs), `adopt-c-bounds-safety` (C).
- `xcrun agent skills export` installs most of Xcode's skills; the accessibility and translation skills come only from `xcrun agent plugin path --plugin-format <agent>`. Skills that call Xcode need `xcrun mcpbridge`.
- Solana: `solana-dev` (`npx skills add solana-foundation/solana-dev-skill`), for on-chain facts only: program IDs, account layouts, instruction rules, and limits. Skip its JavaScript, Rust, and test tooling and its MCP server; this file wins. Before you write or review Solana code, read the reference for the concern:
  - Tokens: `tokens.md`, `kit/programs/token.md`, `kit/programs/token-2022.md`.
  - V1 wire format, resource limits, and priority fees: `transactions-v1.md`, `kit/programs/compute-budget.md`, `concepts.md`.
  - SOL transfers and account creation: `kit/programs/system.md`.
  - Security: `security.md`, the client-side checklist and Token-2022 sections.
  - One-off chain reads during an investigation: `rpc-quick-lookups.md`. V1 errors: `common-errors.md`.

## Project layout

Group files by concern in real folders that Xcode mirrors.

- `Frameworks/<Module>`: `Sources`, `Tests`, and a short, factual `README.md` for outside readers, with no history, progress, or agent-only guidance. Add a Mermaid diagram of a flow, states, or an exchange between parts only where it explains more than a few sentences: a short heading, one or two plain sentences, standard symbols, about 14 nodes at most, and a label on every arrow out of a decision. `Frameworks/TestSupport` holds test helpers that frameworks share.
- `App/Sources`: `Application` (entry and windows, with `Composition`, `Routing`, and `Startup`), `Features/<Feature>` (subfolders only as needed; shared ones move up), `Appearance` (shared theme services and per-window rendering; editing UI and workflows go in `Features/AppearanceSettings`), `UI` (shared `Components`, `Modifiers`, `Styles`, and `Environment`), `Extensions`, `Resources`, and `Configuration`.
- `UI/Environment` declares every custom environment value, one per file; the value's type stays with its owner.
- An extension of a system type is private to its file or lives in `Extensions`, one file per type and concern, such as `Decimal+Rounding.swift`; fluent conveniences stay with their modifier or style. Search there before writing one.
- `App/Tests` mirrors that ownership under `Application`, `Features`, `Appearance`, and `Extensions`. `UI` holds UI tests by feature, `Integration/<Framework>` holds app-hosted framework checks, and `TestSupport` holds helpers shared across concerns, grouped by responsibility and actual consumers. Feature fixtures stay with their tests.

## Architecture

- Separate frameworks by concern and keep them reusable. Internal app services and coordinators compose wallet workflows, outside views. See [references/architecture.md](references/architecture.md).
- Expose only what crosses a module boundary; protocols used inside one module stay internal or private.
- Add a protocol when a role gets a second implementation or tests replace it, and inject it; until then, use the concrete type.
- Workflow models are `<Task>Model`, in the feature's `Models` folder. They hold facts only, as observable state (input, running attempts, typed rejections and errors, completion such as `isSaved`), with no SwiftUI, Accessibility code, or closures that capture view state. Presented views close with `dismiss`; other owners react with `onChange`.
- Root views only own windows and scenes and compose features. Extract a presentation lifecycle into a focused modifier only when it has its own state or several steps; otherwise apply `task` and `alert(error:)` in place.
- Support several wallet windows where the system allows; each keeps its own wallet selection, navigation, and presented tasks. Load appearance and resolve palettes at each window root, and pass palette and tint down through the environment; scenes and screens never receive or load it themselves. Windows share appearance services, not rendered state.

## Code

- Check how Apple solves a problem and mirror its API shape and names before inventing your own; extend the Apple type, such as `URL.persistentDirectory` beside `URL.cachesDirectory`, instead of adding a wrapper. Express intent with typed APIs; services hide serialization and transport.
- Extend a system type only with what belongs to that type everywhere; domain rules stay with the domain type or protocol that owns them.
- No module-name prefixes. Implementations end with their role, such as `JupiterPriceProvider`, as `JSONDecoder` does.
- Error types and properties are `Error` and `error`, never `Failure` or `failure`. Never keep, pass, or show an error as a string, `localizedDescription` included. User-facing errors are payload-free `LocalizedError` enums, with the title in `errorDescription` and the message in `recoverySuggestion`, shown with `alert(error:)`.
- Document production code with DocC: what each type, function, and initializer does, with its parameters, return value, and thrown errors; properties and cases only when their names aren't enough. Write no other comments, none in tests, and never history, sources, versions, rationale, or what other code does. Keep the license header of copied open-source code.
- Don't restate the obvious: no labels or accessibility labels that repeat visible text, a role, or the screen title; no views that only wrap a system view; no tests that check a value against its own declaration.

## SwiftUI

- Small views, such as rows, buttons, and menus, take plain values and bindings, never the models they change. Pass actions as values, structs with `callAsFunction`, and read shared ones from the environment as with `dismiss`. Never store a closure as a view input.
- Customize a control with its style protocol, such as `LabelStyle`, `ButtonStyle`, or `FormStyle`, before adding a view or modifier.
- Each custom modifier, style, or similar SwiftUI API gets a fluent helper, such as a `View` extension or a static member, kept with it; call sites use it. The helper delegates directly, with no duplicate behavior or branched view hierarchy.

## UI

- Navigation, `ArrangementView`, theme packs, and HIG rules: [references/ui.md](references/ui.md).
- A `Form` screen's actions are button rows in its last section, as in Settings: `primary` text, or for destructive actions a `destructive` `warning` label with a trash symbol. `ContentUnavailableView` holds its screen's one action. Input screens instead commit with a prominent symbol-only confirm button at the top toolbar's trailing edge.
- Use the system content margins for `Form`, `List`, and `ScrollView`, capped at the shared 896 pt readable width in wide containers; add no other margins. Inset bars and other window-edge-aligned views with `contentMargins(for: .container)`, read from `GeometryProxy`, never with fixed padding.
- Keep interaction feedback stable: don't flash progress rows, spinners, or disabled states for quick actions, such as preference changes and theme package operations.
- Animate meaningful state changes, row insertion and removal included, with native animations. Check `accessibilityReduceMotion` only for pronounced animations the user names.

## Testing

- Follow [references/testing.md](references/testing.md).
- Test names are sentence-style raw identifiers, not repeated in `@Test` display strings.
- Never reimplement a server's logic in a test RPC; inject a mock RPC when the code only needs one.
- Devnet tests that move funds use the test seed from ignored local configuration, create no wallets, and leave funds with the recipient.

## Solana

- V1 transactions only, built by one shared pipeline from ordered instructions; transfers are instruction helpers. Resource limits and the priority fee go in the message configuration, never in Compute Budget instructions.
- SPL Token and Token-2022 share token-transfer APIs. Agree on each Token-2022 extension with the user before building it.
- Take a mint's token program from the mint account's owner, and use it for all of that mint's instructions and associated token accounts. Check an account's owner before decoding it.
- Move tokens with `TransferChecked`, and create associated token accounts with `CreateIdempotent`. Read decimals from the mint; write them as a number only where the code declares a token by hand, such as a supported-token list.
- Model tokens with Solana's names: `Mint`, `Token` (a token account), and `TokenAmount`. No parallel type for a token fact, and never decimals beside an asset.
- Use one submission strategy: `none` sends through the selected provider; `standard` and `premium` use Sender with its tip. Each transaction goes through one RPC only. See [references/transaction-workflow.md](references/transaction-workflow.md).

## RPC and providers

- No app backend or proxy: the app connects directly to providers, and all RPC, DAS, and price traffic lives in the RPC framework.
- Contracts are provider-neutral. Providers, such as public Solana RPC, Helius, and Jupiter, are interchangeable implementations behind protocols and return shared types.
- Built in: public Solana RPC (no key) and Helius. People can add custom HTTPS RPC URLs that serve standard requests and account, signature, and root subscriptions. Each supports every standard wallet feature. Optional capabilities, such as CDN logos and private balances, are protocols that own their code; each provider declares in `capabilities` the ones its server serves, and a feature the selected provider lacks is skipped, with no request and no error.
- Never ship provider API keys in the bundle or source. People enter them in the app; ignored local configuration supplies them to tests only.
- Add RPC methods only as [references/rpc-scope.md](references/rpc-scope.md) allows.
- Surface rate-limit errors; never retry automatically. Pace price batches within their request budgets; never throttle RPC or DAS requests.

## Wallet and storage

- Recovery material is device-only, never in iCloud sync or backups. See [references/wallet.md](references/wallet.md).
- Never drop saved wallets at launch or during validation; a loading error is a failure, not an empty wallet.
- Token lists are manual, per account. Read balances with standard RPC; use DAS only for logos on the selected provider's CDN, over HTTPS. Never request creator-hosted or off-chain artwork, which exposes the user's IP address. See [references/portfolio.md](references/portfolio.md).
- Files the person would lose go under `URL.persistentDirectory`, which only Reset App deletes; files the app can rebuild, such as balances, go under `URL.ephemeralDirectory`. Each store has its own subfolder. Reset App deletes both, so a new store needs no reset change.

## References

Keep [references/](references/) to approved rules, boundaries, and invariants that the code can't show and that guide new work. No feature specs, screen behavior, API walkthroughs, research, to-dos, history, test results, or unapproved designs.
