# UI architecture

## Composition and navigation

- Build one adaptive SwiftUI interface for iPhone Duo, other iPhones, and iPad. Use the [SwiftUI Expert](plugin://swiftui-expert@swiftui-expert-skill) skill.
- Use `NavigationSplitView` for navigation. Design useful expanded content first, then preserve its hierarchy and functionality when columns collapse. Size content from the available space, safe areas, and system layout information.
- Preserve selection, navigation, scroll position, and unfinished input across resizing, folding, and theme changes. Keep native navigation, toolbar placement, menus, and presentation behavior.
- Use standard Dynamic Type without custom size caps. Adapt layouts through stacking, scrolling, and column collapse.
- Keep app composition, scene state, feature coordination, feature views, and appearance as separate internal app concerns. Inject services through protocols; views present state and capture intent.
- `SettingsScene` owns the settings split view and each window's navigation selection. Appearance is a destination within that container.
- Every settings sidebar destination uses a native `Label` with an SF Symbol and text, including when the navigation collapses on compact displays.
- Reuse the existing portfolio coordinator and its lifecycle contract. Layout and theme changes must not recreate it or restart observation. Preserve the display distinctions in [Portfolio](portfolio.md).

## Multiple windows

- Support multiple wallet windows through `WindowGroup` wherever the system supports them, including iPad and iPhone Duo's inner display. New-window availability can change as Duo closes; respect current availability and handle failed requests.
- Each window owns its wallet and network selection, navigation, presented tasks, and portfolio coordinator. Changing the wallet in one window must not change another window's selection or workflow.
- Drive portfolio observation from the owning scene's activity. Closing or deactivating one window detaches its consumers without stopping other windows or removing wallet data.
- Share underlying services across windows with the same configuration, including portfolio caching, wallet subscriptions, and price-provider pacing. Keep networks isolated and replace a window's portfolio coordinator when its network changes.
- Transaction review and approval remain bound to the initiating window's exact message, account, and network. Opening another window does not grant approval.
- Window opening and restoration carry only non-secret identifiers and presentation state. Recovery material remains exclusively under the [Wallet](wallet.md) storage and access rules.

## Theme packs

The [Themes framework contract](../Themes/README.md) defines package structure, authoring, manifest fields, import errors, and export. The framework is included in the app and currently supports color tokens and bundled images. Typography and other component tokens remain deferred.

- Support an arbitrary number of built-in and custom theme packs with supported layout variants. Represent packs as versioned data and visual assets consumed through shared components.
- Built-in themes cannot be edited, replaced, or removed by users. Custom/imported themes can be removed.
- Make app components themeable from their first implementation through explicit appearance inputs. Share data and behavior across visual variants. Start with the agreed default and add variants only for concrete, approved designs; keep component APIs small.
- Define semantic tokens by purpose, independent of particular screens. Add screen-specific layout choices only as their component designs are approved.
- Supply the framework with the complete app-owned baseline and resolve omitted settings before rendering. Views consume complete values without repeating fallback logic.
- Theme imports must keep rendering responsive. Run package I/O and validation in the background, outside the main actor and Swift's shared executor; verify frame pacing on devices when import presentation is integrated.
- Separate the pack catalog, appearance preferences, and each window's resolved theme. Packs describe semantic style roles, scalable typography, visual assets, decoration, and app-supported layout choices.
- The internal [ThemeCatalog](../widgets/Themes/Catalog/ThemeCatalog.swift) implements `ThemeCatalogProviding` for shared local installations. It lists metadata without loading package images, preserves omitted settings in installed copies, and keeps filesystem work off the main actor and Swift's shared executor. Importing installs without selecting a theme. Custom replacement requires the exact approved installed revision; duplicate display names are allowed when IDs differ.
- Use an app-wide default theme with optional per-wallet overrides. Windows showing the same wallet use its selected theme; wallets without an override follow the app-wide default.
- The internal [AppearanceStore](../widgets/Themes/Preferences/AppearanceStore.swift) persists selections by stable wallet ID. Removing a custom theme atomically clears its selections. An affected app default returns to the original built-in appearance; affected wallet overrides return to following the app default. Other selections remain intact, and reinstalling a removed identity does not reactivate it. Reset clears all selections and retains installed packs.
- Share one [AppearanceCoordinator](../widgets/Themes/Coordination/AppearanceCoordinator.swift) across windows using the same catalog configuration. Its cached snapshot contains IDs and catalog revisions; selection lookup performs no disk or package reads. Activate it when each window becomes active and reload it after catalog mutations. Each window's resolved colors and assets remain separate from these preferences.
- Themes may change semantic colors, backgrounds, textures, borders, and shapes; Dynamic Type-aware typography; content treatments such as asset rows versus cards or balance-summary compositions; and spacing and decorative motion within supported ranges.
- Packs select app-implemented presentation variants for individual components, such as asset rows or cards. Each variant adapts to compact and expanded space and accessibility settings. The app owns adaptation and rendering; packs contain data and assets without executable UI code.
- Keep navigation behavior, action meanings, Dynamic Type, accessibility semantics, and transaction-review requirements app-owned. Themes cannot remove required transaction information or approval controls, or alter their behavior.
- Keep import validation limited to package structure, supported settings and asset formats, and safe asset loading. Within supported capabilities, let users choose their appearance; do not reject or rewrite custom packs for contrast, aesthetic choices, or HIG conformance.
- Reject structurally invalid or unsupported supplied settings with clear import errors and leave the installed theme unchanged. Omitted settings continue to use defaults.
- The app's page in iOS Settings includes a one-time **Reset Appearance** switch. On the next launch or window activation, it clears the app default and all wallet overrides, retains installed packs, and turns itself off after a successful reset. A failed reset leaves the switch enabled for the next activation. Concurrent window activations share one recovery operation; closing a window does not cancel it. Recovery does not load theme packages.

## Design requirements

### Appearance settings

- **App Theme** lists built-in and imported themes inline and selects the shared default. Imported themes appear once, with swipe-to-delete and confirmation of the exact installed revision; built-ins have no delete action. **Wallet Theme** opens a separate chooser when the owning window has a selected wallet and offers **Use App Default** or an explicit theme, including Original.
- Swipe actions show symbols without visible captions and retain descriptive accessibility labels. Delete uses a white trash symbol on a system-red background.
- Both selectors use native name-and-checkmark rows without previews. Checkmarks and appearance update after persistence succeeds. Saving a selection shows no transient progress row or disabled-state flash.
- **Theme Packs** provides Files import and default-template export. Custom-theme export is unsupported. Import installs without selecting; replacement requires confirmation of the exact installed revision.
- Original uses adaptive system colors. Exported templates contain complete defaults and a new custom identity. Color conversion happens when the selected package revision changes; rendering and trait changes use cached palettes.
- Work and confirmations belong to the initiating window; committed changes publish to the shared appearance snapshot. Errors preserve installed data and the last committed preferences. An unreadable selected package renders Original and reports the failure.

### Visual direction

- Use native appearance as the baseline, with a distinctive visual identity led by color and typography using iOS-provided fonts. Use [Family](https://family.co/) as a reference for this direction; native navigation does not prescribe the Settings app's visual treatment. Specific palettes, text styles, and component designs require separate agreement. Theme-pack typography remains deferred.
- Before implementing each UI concern, agree on its screen structure, visible content, actions, and user-facing states and behavior. Resolve missing or conflicting decisions with the user; architectural constraints and HIG guidance do not supply product-design approval.
- Before finalizing the theme architecture, review disposable SwiftUI mockups on iPhone Duo, a regular iPhone, and iPad. Compare a native baseline, a bold graphic theme, and a restrained textured theme, including meaningful layout differences. Use sample presentation data and keep the mockups separate from production views and service integration.
- Disposable mockups do not approve production screens or themes. Keep their code, themes, assets, and captures outside the repository and app; never include them in commits.
- Review every applicable Apple Human Interface Guideline for app-owned UI and built-in themes, and resolve known violations before accepting that work. User-created packs are not subject to HIG approval; successful import does not certify rendered compliance.
- Verify supported layouts and built-in themes across Duo transitions, compact iPhones, iPad resizing, large text, VoiceOver, keyboard interaction, contrast settings, and reduced motion.
- Keep guidance linked to Apple's Markdown sources; consult the relevant component and interaction guidance as each feature is designed.

## Apple guidance

- [Human Interface Guidelines](https://developer.apple.com/tutorials/data/design/human-interface-guidelines.md)
- [Designing for iPhone Duo](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [Layout](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.md)
- [Sidebars](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sidebars.md)
- [Branding](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/branding.md)
- [Accessibility](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.md)
- [Color](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.md)
- [Typography](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.md)
- [Images](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/images.md)
- [Settings bundles](https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app.md)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup.md)
- [Multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
