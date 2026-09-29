# UI architecture

## Composition and navigation

- Build one adaptive SwiftUI interface for iPhone Duo, other iPhones, and iPad. Use the [SwiftUI Expert](plugin://swiftui-expert@swiftui-expert-skill) skill.
- Use `NavigationSplitView` for navigation. Design useful expanded content first, then preserve its hierarchy and functionality when columns collapse. Size content from the available space, safe areas, and system layout information.
- Preserve selection, navigation, scroll position, and unfinished input across resizing, folding, and theme changes. Keep native navigation, toolbar placement, menus, and presentation behavior.
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

- Support an arbitrary number of built-in and custom theme packs with supported layout variants. Represent packs as versioned data and visual assets consumed through shared components.
- Use an app-wide default theme with optional per-wallet overrides. Windows showing the same wallet use its selected theme; wallets without an override follow the app-wide default.
- Themes may change semantic colors, backgrounds, textures, borders, and shapes; typography within readable, Dynamic Type-aware limits; content treatments such as asset rows versus cards or balance-summary compositions; and spacing and decorative motion within supported ranges.
- Each supported layout variant adapts to compact and expanded space and accessibility settings. Themes select supported variants; the app owns adaptation and rendering.
- Keep navigation behavior, action meanings, accessibility semantics, and transaction-review requirements app-owned. Themes cannot hide required transaction information or approval controls.
- Validate imported packs and provide safe appearance fallbacks. Accessibility settings and readable content take precedence over decorative choices.

## Design requirements

- Review every applicable Apple Human Interface Guideline and resolve known violations before accepting UI work. Track applicability and verification without treating an architectural decision or successful theme import as proof of rendered compliance.
- Verify supported layouts and themes across Duo transitions, compact iPhones, iPad resizing, large text, VoiceOver, keyboard interaction, contrast settings, and reduced motion.
- Keep guidance linked to Apple's Markdown sources; consult the relevant component and interaction guidance as each feature is designed.

## Apple guidance

- [Human Interface Guidelines](https://developer.apple.com/tutorials/data/design/human-interface-guidelines.md)
- [Designing for iPhone Duo](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [Layout](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.md)
- [Branding](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/branding.md)
- [Accessibility](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.md)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup.md)
- [Multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
