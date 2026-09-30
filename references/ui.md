# UI architecture

## Composition and navigation

- Build one adaptive SwiftUI interface for iPhone Duo, other iPhones, and iPad. Use the [SwiftUI Expert](plugin://swiftui-expert@swiftui-expert-skill) skill.
- Use `NavigationSplitView` for navigation. Design useful expanded content first, then preserve its hierarchy and functionality when columns collapse. Size content from the available space, safe areas, and system layout information.
- Preserve selection, navigation, scroll position, and unfinished input across resizing, folding, and theme changes. Keep native navigation, toolbar placement, menus, and presentation behavior.
- Use standard Dynamic Type without custom size caps. Adapt layouts through stacking, scrolling, and column collapse.
- Keep app composition, scene state, feature coordination, feature views, and appearance as separate internal app concerns. Inject services through protocols; views present state and capture intent.
- Reuse the existing portfolio coordinator and its lifecycle contract. Layout and theme changes must not recreate it or restart observation. Preserve the display distinctions in [Portfolio](portfolio.md).

## Multiple windows

- Support multiple wallet windows through `WindowGroup` wherever the system supports them, including iPad and iPhone Duo's inner display. New-window availability can change as Duo closes; respect current availability and handle failed requests.
- Each window owns its wallet and network selection, navigation, presented tasks, and portfolio coordinator. Changing the wallet in one window must not change another window's selection or workflow.
- Drive portfolio observation from the owning scene's activity. Closing or deactivating one window detaches its consumers without stopping other windows or removing wallet data.
- Share underlying services across windows with the same configuration, including portfolio caching, wallet subscriptions, and price-provider pacing. Keep networks isolated and replace a window's portfolio coordinator when its network changes.
- Transaction review and approval remain bound to the initiating window's exact message, account, and network. Opening another window does not grant approval.
- Window opening and restoration carry only non-secret identifiers and presentation state. Recovery material remains exclusively under the [Wallet](wallet.md) storage and access rules.

## Theme packs

The [Themes framework contract](../Themes/README.md) defines package structure, authoring, manifest fields, import errors, export, and versioning. The framework will be included in the app; implementation of its target and services remains pending.

- Support an arbitrary number of built-in and custom theme packs with supported layout variants. Represent packs as versioned data and visual assets consumed through shared components.
- Define semantic tokens by purpose, independent of particular screens. Add screen-specific layout choices only as their component designs are approved.
- Supply the framework with the complete app-owned baseline and resolve omitted settings before rendering. Views consume complete values without repeating fallback logic.
- Separate the pack catalog, appearance preferences, and each window's resolved theme. Packs describe semantic style roles, scalable typography, visual assets, decoration, and app-supported layout choices.
- Use an app-wide default theme with optional per-wallet overrides. Windows showing the same wallet use its selected theme; wallets without an override follow the app-wide default.
- Themes may change semantic colors, backgrounds, textures, borders, and shapes; Dynamic Type-aware typography; content treatments such as asset rows versus cards or balance-summary compositions; and spacing and decorative motion within supported ranges.
- Each supported layout variant adapts to compact and expanded space and accessibility settings. Themes select supported variants; the app owns adaptation and rendering.
- Keep navigation behavior, action meanings, Dynamic Type, accessibility semantics, and transaction-review requirements app-owned. Themes cannot remove required transaction information or approval controls, or alter their behavior.
- Keep import validation limited to package structure, supported settings and asset formats, and safe asset loading. Within supported capabilities, let users choose their appearance; do not reject or rewrite custom packs for contrast, aesthetic choices, or HIG conformance.
- Reject structurally invalid or unsupported supplied settings with clear import errors and leave the installed theme unchanged. Omitted settings continue to use defaults.
- Provide recovery from the app's page in iOS Settings that restores the original built-in appearance when a custom theme makes the app unusable. Recovery must remain accessible outside the themed app UI.

## Design requirements

- Before implementing each UI concern, agree on its screen structure, visible content, actions, and user-facing states and behavior. Resolve missing or conflicting decisions with the user; architectural constraints and HIG guidance do not supply product-design approval.
- Before finalizing the theme architecture, review disposable SwiftUI mockups on iPhone Duo, a regular iPhone, and iPad. Compare a native baseline, a bold graphic theme, and a restrained textured theme, including meaningful layout differences. Use sample presentation data and keep the mockups separate from production views and service integration.
- Disposable mockups do not approve production screens or themes. Keep their implementation outside `main` and production sources.
- Review every applicable Apple Human Interface Guideline for app-owned UI and built-in themes, and resolve known violations before accepting that work. User-created packs are not subject to HIG approval; successful import does not certify rendered compliance.
- Verify supported layouts and built-in themes across Duo transitions, compact iPhones, iPad resizing, large text, VoiceOver, keyboard interaction, contrast settings, and reduced motion.
- Keep guidance linked to Apple's Markdown sources; consult the relevant component and interaction guidance as each feature is designed.

## Apple guidance

- [Human Interface Guidelines](https://developer.apple.com/tutorials/data/design/human-interface-guidelines.md)
- [Designing for iPhone Duo](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [Layout](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.md)
- [Branding](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/branding.md)
- [Accessibility](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.md)
- [Color](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.md)
- [Typography](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.md)
- [Images](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/images.md)
- [Settings bundles](https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app.md)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup.md)
- [Multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
