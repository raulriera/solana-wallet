import Foundation

/// A theme error that an alert explains without the underlying error's text.
nonisolated enum ThemeError: LocalizedError, Equatable {
    /// The window's selected theme couldn't be loaded, so it is no longer selected.
    case themeUnreadable
    /// The saved theme choices couldn't be loaded.
    case settingsUnreadable
    /// A theme file couldn't be imported.
    case importFailed
    /// The theme template couldn't be exported.
    case exportFailed
    /// A theme choice or catalog change couldn't be saved.
    case saveFailed
    /// A built-in theme can't be replaced or removed.
    case builtInTheme
    /// Another window changed the theme first.
    case changedElsewhere

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .themeUnreadable, .settingsUnreadable: String(localized: "Couldn't Load Theme")
        case .importFailed: String(localized: "Couldn't Import Theme")
        case .exportFailed: String(localized: "Couldn't Export Theme")
        case .saveFailed, .builtInTheme, .changedElsewhere: String(localized: "Couldn't Change Theme")
        }
    }

    /// The alert's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .themeUnreadable: String(localized: "Your theme couldn't be loaded and is no longer selected.")
        case .settingsUnreadable: String(localized: "Your appearance settings couldn't be loaded.")
        case .importFailed: String(localized: "This file isn't a valid theme.")
        case .exportFailed: String(localized: "The theme template couldn't be exported.")
        case .saveFailed: String(localized: "Your appearance settings couldn't be saved. Try again.")
        case .builtInTheme: String(localized: "Built-in themes cannot be replaced or removed.")
        case .changedElsewhere: String(localized: "This theme changed in another window. Try again.")
        }
    }
}
