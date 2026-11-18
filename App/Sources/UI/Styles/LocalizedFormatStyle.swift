import Foundation

/// A format style that formats with a locale that callers can replace.
nonisolated protocol LocalizedFormatStyle: FormatStyle {
    var locale: Locale { get set }
}

nonisolated extension LocalizedFormatStyle {
    /// Returns a copy of the style that formats with a locale.
    ///
    /// - Parameter locale: The locale to format with.
    /// - Returns: The style with the locale.
    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}
