# UI architecture

## Composition and navigation

- Build one adaptive SwiftUI interface for iPhone Duo, other iPhones, and iPad. Use the [SwiftUI Expert](plugin://swiftui-expert@swiftui-expert-skill) skill.
- Use a `TabView` with a fixed tab bar for the main app's sections, with a `NavigationSplitView` in each section. Onboarding is a linear flow owned by `OnboardingScene`'s `NavigationStack`. Screens with two peer regions, such as onboarding's introduction and actions, use an `ArrangementView`, with scrolling inside each region where content can outgrow it. Design useful expanded content first, then preserve its hierarchy and functionality when columns collapse. Size content from the available space, safe areas, and system layout information.
- A section with nothing to show in any column replaces its split view with one full-width empty screen and its one action, never an empty state in each column. The split view appears once a column has content.
- Lay content out against the container's margins, which on iPhone Duo are asymmetric: 0 pt beside a vertical bar and the usual 16–20 pt elsewhere. `Form` and `List` apply them, so custom rows, such as token cards, keep the list's margins. Bars and other views aligned to the window's edges use `contentMargins(for: .container, edges:)`, and layout calculations read `GeometryProxy.contentMargins(for:edges:)`. The guide follows the window's edges only: it is 0 pt where an `ArrangementView`'s regions meet, so content in those regions keeps its own padding. Hardcoded margin values are not used for these margins; padding inside a card or control is the component's own spacing.
- Preserve selection, navigation, scroll position, and unfinished input across resizing, folding, and theme changes. Keep native navigation, toolbar placement, menus, and presentation behavior.
- Use native motion to communicate meaningful state changes. Animate theme-list insertion, removal, and reordering after catalog changes commit using the system default animation. Keep animation scoped to the changing content. Add explicit Reduce Motion adaptations only for pronounced animations identified by the user.
- Cap Dynamic Type at the largest standard size (xxxLarge) with `limitedTextSize()` at each window's root and in each sheet, which doesn't inherit the window's cap; the accessibility sizes are not supported. Adapt layouts within that range through stacking, scrolling, and column collapse. The payment keypad's keys show the large content viewer.
- Use system semantic colors, such as the secondary label gray and system red, as Apple ships them, even below 4.5:1 contrast. Contrast requirements apply to colors the app computes, such as token card tints.
- Keep app composition, scene state, feature coordination, feature views, and appearance as separate internal app concerns. Inject services through protocols; views present state and capture intent.
- A task's workflow model publishes what happened; its views decide how it feels. Wrap the person's actions in `withAnimation` where the view calls the model, animate later results with `animation(_:value:)` on light keys, signal with `sensoryFeedback`, and post VoiceOver announcements from `onChange`.
- Startup reads public account metadata before choosing a destination. Open the window's restored account while it is still saved, otherwise the first saved account, or onboarding only after a successful empty read. Loading failures offer an explicit retry without resetting storage; startup never accesses recovery material or replaces a window's resolved selection.
- After saving a wallet, onboarding shows Providers, as in Settings, with Continue to open the wallet. Solana's public RPC (free, no key) is in use until a person chooses another provider; keyed providers verify the key before they're chosen, and a key entered to choose one opens the wallet once that provider is chosen.
- A missing or rejected provider key, or a custom RPC in a Devnet window, replaces only the portfolio with an error screen. Key errors reopen provider setup.
- `SettingsScene` owns the settings split view and each window's navigation selection. Compact displays open on the sidebar list.
- One control idiom opens one kind of navigation: a row's info button always pushes its details. Among provider screens, only key entry for a chosen provider is a sheet.
- Every settings sidebar destination uses a native `Label` with an SF Symbol and text, including when the navigation collapses on compact displays. Symbols use multicolor rendering and turn monochrome on a selected row with the accent background.
- **Network** chooses Mainnet or Devnet for the owning window with native name-and-checkmark rows; other windows keep theirs. A change gives the window a new portfolio coordinator and returns the portfolio to its token list.
- **Security & Privacy** shows the window's wallet backup after biometric or passcode authentication: its words with Copy, any BIP-39 passphrase, and the account path. Words hide while the scene is inactive or captured and leave memory when the screen closes. A missing recovery explains that the app must be reset.
- **Reset App** asks for biometrics or the passcode, then shows two confirmation screens. It skips authentication when the device has no passcode or when it starts from a missing recovery. It deletes every recovery phrase, then the saved and cached folders, including wallet metadata and themes, then the provider key and custom RPCs. After a successful reset, every window returns to Welcome and Mainnet with fresh onboarding state, including windows already setting up a wallet; their previous setup tasks are cancelled. The reset screens explain this scope, and each window's next wallet opens on Portfolio. A failed step offers Try Again, which deletes what remains.
- Reuse the existing portfolio coordinator and its lifecycle contract. Layout, theme, and tab changes must not recreate it or restart observation. Preserve the display distinctions in [Portfolio](portfolio.md).
- The token list's **Add Token** button opens a native sheet that the system places on each display. People paste a mint address and check the token's preview before adding it; the token appears with the next balances.

## Multiple windows

- Support multiple wallet windows through `WindowGroup` wherever the system supports them, including iPad and iPhone Duo's inner display. New-window availability can change as Duo closes; respect current availability and handle failed requests.
- Each window owns its wallet and network selection, navigation, presented tasks, and portfolio coordinator. Changing the wallet in one window must not change another window's selection or workflow.
- The RPC provider choice applies to every window.
- Drive portfolio observation from the owning scene's activity. Closing or deactivating one window detaches its consumers without stopping other windows or removing wallet data.
- Share underlying services across windows with the same configuration, including portfolio caching, wallet subscriptions, and price-provider pacing. Keep networks isolated and replace a window's portfolio coordinator when its network changes.
- Transaction review and approval remain bound to the initiating window's exact message, account, and network. Opening another window does not grant approval.
- Window opening and restoration carry only non-secret identifiers and presentation state. Recovery material remains exclusively under the [Wallet](wallet.md) storage and access rules.
- Restore each window's section, wallet, and network with `SceneStorage` after the system ends the app; removing the app in the app switcher starts fresh. Each container owns its keys, named after the owner, and drops identifiers that no longer resolve. Stored raw values are permanent: add cases, never rename or reuse them. Never restore key input, transaction review, or provider data.

## Theme packs

The [Themes framework contract](../Frameworks/Themes/README.md) defines package structure, authoring, manifest fields, import errors, and export. The framework is included in the app and currently supports color tokens and bundled images. Typography and other component tokens remain deferred.

- Support an arbitrary number of built-in and custom theme packs with supported layout variants. Represent packs as versioned data and visual assets consumed through shared components.
- Built-in themes cannot be edited, replaced, or removed by users. Custom/imported themes can be removed.
- Make app components themeable from their first implementation through the owning window's appearance environment. Read semantic colors where they are used instead of forwarding palettes through initializers. Share data and behavior across visual variants. Start with the agreed default and add variants only for concrete, approved designs; keep component APIs small.
- Define semantic tokens by purpose, independent of particular screens. Add screen-specific layout choices only as their component designs are approved.
- Supply the framework with the complete app-owned baseline and resolve omitted settings before rendering. Views consume complete values without repeating fallback logic.
- Theme imports must keep rendering responsive. Run package I/O and validation in the background, outside the main actor and Swift's shared executor, and check frame pacing on a device after changing import presentation.
- Separate the pack catalog, appearance preferences, and each window's resolved theme. Packs describe semantic style roles, scalable typography, visual assets, decoration, and app-supported layout choices.
- The internal [ThemeCatalog](../App/Sources/Appearance/Catalog/ThemeCatalog.swift) implements `ThemeCatalogProviding` for shared local installations. It lists metadata without loading package images, preserves omitted settings in installed copies, and keeps filesystem work off the main actor and Swift's shared executor. Importing installs without selecting a theme. Custom replacement requires the exact approved installed revision; duplicate display names are allowed when IDs differ.
- Use an app-wide default theme with optional per-wallet overrides. Windows showing the same wallet use its selected theme; wallets without an override follow the app-wide default.
- The internal [AppearanceStore](../App/Sources/Appearance/Preferences/AppearanceStore.swift) persists selections by stable wallet ID. Removing a custom theme atomically clears its selections. An affected app default returns to the original built-in appearance; affected wallet overrides return to following the app default. Other selections remain intact, and reinstalling a removed identity does not reactivate it. Reset clears all selections and retains installed packs.
- Share one [AppearanceCoordinator](../App/Sources/Appearance/Coordination/AppearanceCoordinator.swift) across windows using the same catalog configuration. Its cached snapshot contains IDs and catalog revisions; selection lookup performs no disk or package reads. Activate it when each window becomes active and reload it after catalog mutations. Each window's resolved colors and assets remain separate from these preferences.
- Own the rendered appearance, theme loading, and loading errors once at the root of each window, above feature navigation. [WindowRoot](../App/Sources/Application/WindowRoot.swift) injects the resolved palette and native tint into its descendants; onboarding follows the app-wide default. Feature scenes inherit those values without creating another renderer or repeating theme loading. Preserve the window's renderer across feature, layout, and theme changes.
- Themes may change semantic colors, backgrounds, textures, borders, and shapes; Dynamic Type-aware typography; content treatments such as asset rows versus cards or balance-summary compositions; and spacing and decorative motion within supported ranges.
- Packs select app-implemented presentation variants for individual components, such as asset rows or cards. Each variant adapts to compact and expanded space and accessibility settings. The app owns adaptation and rendering; packs contain data and assets without executable UI code.
- Row layouts use native `List` selection and sidebar styling with no custom selection indicators. Only the card layout is custom, and each layout is its own container.
- Token cards and rows show the symbol and name, then the value and the 24-hour change as an up or down arrow with a percentage. The balance takes the value's place when the value is unknown; the detail screen shows the balance, and the value, price, and 24-hour change only when known, so devnet tokens show only their balance and a note that they have no monetary value. Cards and rows shorten values and balances from 10,000 up to one decimal, as in 10.2K; the detail screen and VoiceOver use the full number. Supporting text on cards uses a secondary color that keeps 4.5:1 contrast.
- Keep navigation behavior, action meanings, Dynamic Type, accessibility semantics, and transaction-review requirements app-owned. Themes cannot remove required transaction information or approval controls, or alter their behavior.
- Keep import validation limited to package structure, supported settings and asset formats, and safe asset loading. Within supported capabilities, let users choose their appearance; do not reject or rewrite custom packs for contrast, aesthetic choices, or HIG conformance.
- Reject structurally invalid or unsupported supplied settings with clear import errors and leave the installed theme unchanged. Omitted settings continue to use defaults.
- The app's page in iOS Settings includes a one-time **Reset Appearance** switch. On the next launch or window activation, it clears the app default and all wallet overrides, retains installed packs, and turns itself off after a successful reset. A failed reset leaves the switch enabled for the next activation. Concurrent window activations share one recovery operation; closing a window does not cancel it. Recovery does not load theme packages.

## Design requirements

### Appearance settings

- **App Theme** lists built-in and imported themes inline and selects the shared default. Imported themes appear once, with swipe-to-delete and confirmation of the exact installed revision; built-ins have no delete action. **Wallet Theme** opens a separate chooser when the owning window has a selected wallet and offers **Use App Default** or an explicit theme, including Original.
- Swipe actions show symbols without visible captions and retain descriptive accessibility labels. Delete uses a white trash symbol on a system-red background.
- Both selectors use native name-and-checkmark rows without previews. Checkmarks and appearance update after persistence succeeds. Saving a selection shows no transient progress row or disabled-state flash.
- **Theme Packs** provides Files import and default-template export. Custom-theme export is unsupported. Import installs without selecting; replacement requires confirmation of the exact installed revision. Package operations do not insert temporary status rows or flash the form's disabled state; committed catalog changes update the theme list.
- Original uses adaptive system colors. Exported templates contain complete defaults and a new custom identity. Color conversion happens when the selected package revision changes; rendering and trait changes use cached palettes.
- Work and confirmations belong to the initiating window; committed changes publish to the shared appearance snapshot. Errors preserve installed data and the last committed preferences. An unreadable selected package renders Original and reports the failure.

### Visual direction

- Use native appearance as the baseline, with a distinctive visual identity led by color and typography using iOS-provided fonts. Use [Family](https://family.co/) as a reference for this direction; native navigation does not prescribe the Settings app's visual treatment. Specific palettes, text styles, and component designs require separate agreement.
- Before implementing each UI concern, agree on its screen structure, visible content, actions, and user-facing states and behavior. Resolve missing or conflicting decisions with the user; architectural constraints and HIG guidance do not supply product-design approval.
- Disposable mockups use sample presentation data, stay separate from production views and service integration, and do not approve production screens or themes. Keep their code, themes, assets, and captures outside the repository and app; never include them in commits.
- Review every applicable Apple Human Interface Guideline for app-owned UI and built-in themes, and resolve known violations before accepting that work. User-created packs are not subject to HIG approval; successful import does not certify rendered compliance.
- Verify supported layouts and built-in themes across Duo transitions, compact iPhones, iPad resizing, large text, VoiceOver, keyboard interaction, contrast settings, and reduced motion.
- Keep guidance linked to Apple's Markdown sources; consult the relevant component and interaction guidance as each feature is designed.

## Apple guidance

- [Human Interface Guidelines](https://developer.apple.com/tutorials/data/design/human-interface-guidelines.md)
- [Designing for iPhone Duo](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo.md)
- [Layout](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.md)
- [`contentMargins(for:edges:alignment:)`](https://developer.apple.com/documentation/swiftui/view/contentmargins(for:edges:alignment:).md) and [`ContentMarginGuide.container`](https://developer.apple.com/documentation/swiftui/contentmarginguide/container.md)
- [Motion](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/motion.md)
- [Sidebars](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sidebars.md)
- [Branding](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/branding.md)
- [Accessibility](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.md)
- [Color](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.md)
- [Typography](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.md)
- [Images](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/images.md)
- [Settings bundles](https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app.md)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup.md)
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
