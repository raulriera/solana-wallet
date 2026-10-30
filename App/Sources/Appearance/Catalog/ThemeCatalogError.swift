/// An error from a theme catalog operation.
nonisolated enum ThemeCatalogError: Error, Sendable, Equatable {
    case builtInTheme
    /// An installed theme has the same identity.
    case replacementRequired(ThemeEntry)
    /// The entry changed after the caller read it.
    case changed
    case invalidStorage
}
