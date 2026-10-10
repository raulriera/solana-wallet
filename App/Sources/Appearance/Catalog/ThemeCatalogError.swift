/// A catalog operation cannot proceed with the supplied identity or revision.
nonisolated enum ThemeCatalogError: Error, Sendable, Equatable {
    case builtInTheme
    case replacementRequired(ThemeEntry)
    case changed
    case invalidStorage
    case duplicateBuiltIn
}
