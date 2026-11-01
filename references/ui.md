# UI architecture

## Navigation

- Build one adaptive SwiftUI interface for iPhone Duo, other iPhones, and iPad.
- Use a `TabView` with a fixed tab bar and a `NavigationSplitView` in each section. Onboarding is the approved exception: a linear `NavigationStack` in `OnboardingScene`.
- A screen with two peer regions uses an `ArrangementView`, with scrolling inside each region where content can outgrow it.
- A section with nothing to show in any column replaces its split view with one full-width empty screen and its one action.
- Settings sidebar destinations use a native `Label` with a multicolor SF Symbol.
- A What's New screen is a sheet with a bold title, up to three features, and one prominent Continue button, as Shortcuts shows it. Each feature is a tinted SF Symbol, a bold title, and one short sentence.
- Preserve selection, navigation, scroll position, and unfinished input across resizing, folding, and theme changes.

## Layout

- Lay content out against the container's margins, which on iPhone Duo are asymmetric: 0 pt beside a vertical bar. `Form` and `List` apply them, so custom rows keep the list's margins. Bars and other window-edge views use `contentMargins(for: .container, edges:)`, and layout reads `GeometryProxy.contentMargins(for:edges:)`. The guide is 0 pt where an `ArrangementView`'s regions meet, so content there keeps its own padding.
- Cap Dynamic Type at xxxLarge with `limitedTextSize()` at each window's root and in each sheet. Accessibility sizes aren't supported; adapt with stacking, scrolling, and column collapse.
- Use system semantic colors as Apple ships them. Contrast rules apply to colors the app computes.
- Views own how a result feels: `withAnimation` where the view calls the model, `animation(_:value:)` for later results, `sensoryFeedback`, and VoiceOver announcements from `onChange`.

## Windows

- Support multiple windows through `WindowGroup` wherever the system allows. New-window availability can change as Duo closes.
- Each window owns its wallet and network selection, navigation, and presented tasks. Provider and currency choices apply to every window.
- Startup reads public account metadata only: open the restored account while it is saved, else its wallet's first account, else the first saved account, and onboarding only after a successful empty read. A loading error offers a retry; it never resets storage or reads recovery.
- Transaction review and approval stay bound to the initiating window.
- `SceneStorage` restores each window's section, account and wallet IDs, and network. Each container owns keys named after it and drops IDs that no longer resolve. Stored raw values are permanent: add cases, never rename or reuse them. Never store secrets, key input, transaction review, or provider data.
- Scene activity drives observation. Windows share services with the same configuration; networks stay isolated.

## Theme packs

The [Themes framework](../Frameworks/Themes/README.md) defines the package format. Packs support color tokens and images; typography and component tokens are deferred.

- Packs are data and assets, never executable UI. The app owns rendering, adaptation, navigation, action meanings, Dynamic Type, accessibility, and transaction review; a theme can't remove required transaction information or approval controls.
- Built-in themes can't be edited or removed; custom themes can. An app-wide default applies, with an optional override for each wallet.
- [WindowRoot](../App/Sources/Application/WindowRoot.swift) resolves the appearance once per window. Feature views read semantic colors from the environment where they use them.
- Package I/O and validation run off the main actor and Swift's shared executor.
- Validate only structure, supported settings and formats, and safe asset loading. Invalid settings fail with a clear error and leave the installed theme unchanged. Never reject a custom pack for contrast, aesthetics, or HIG conformance.

## Design approval

- Before building a UI concern, agree with the user on its structure, content, actions, and states. Architecture and the HIG don't approve product design.
- Mockups use sample data, stay outside the repository, and never approve production screens.
- Review the applicable HIG for app-owned UI and built-in themes. The visual direction is native with a distinctive identity led by color and iOS fonts, with [Family](https://family.co/) as a reference; palettes and component designs need separate agreement.
- Verify Duo transitions, compact iPhones, iPad resizing, large text, VoiceOver, keyboard, contrast settings, and reduced motion.

## Apple guidance

- [Human Interface Guidelines](https://developer.apple.com/tutorials/data/design/human-interface-guidelines.md)
- [Designing for iPhone Duo](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo.md)
- [`contentMargins(for:edges:alignment:)`](https://developer.apple.com/documentation/swiftui/view/contentmargins(for:edges:alignment:).md)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup.md)
