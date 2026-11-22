import Foundation

/// A format style that keeps a name as typed and strongly emphasizes its given name, as Contacts shows Adam in Adam Okon.
nonisolated struct EmphasizedGivenNameFormatStyle: FormatStyle {
    func format(_ name: String) -> AttributedString {
        var formatted = AttributedString(name)
        if let givenName = (try? PersonNameComponents(name))?.givenName, let range = formatted.range(of: givenName) {
            formatted[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return formatted
    }
}

nonisolated extension FormatStyle where Self == EmphasizedGivenNameFormatStyle {
    /// A name as typed, with its given name strongly emphasized.
    static var emphasizedGivenName: Self { Self() }
}
