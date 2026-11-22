import Foundation
import Transactions

/// A format style that abbreviates a recipient to its name's initials and a trailing number of up to two digits, as
/// in AO for Adam Okon and A2 for Account 2, or to its address's monogram when it has no name to abbreviate.
nonisolated struct MonogramFormatStyle: LocalizedFormatStyle {
    var locale: Locale = .autoupdatingCurrent

    func format(_ recipient: PaymentRecipient) -> String {
        guard let name = recipient.name, let components = try? PersonNameComponents(name) else {
            return recipient.address.formatted(.monogram)
        }
        let lastWord = name.split(whereSeparator: \.isWhitespace).last ?? ""
        let number = lastWord.count <= 2 && lastWord.allSatisfy(\.isWholeNumber) ? lastWord : ""
        return components.formatted(.name(style: .abbreviated).locale(locale)) + number
    }
}

nonisolated extension FormatStyle where Self == MonogramFormatStyle {
    /// A recipient's initials and trailing number, or its address's monogram when it has no name to abbreviate.
    static var monogram: Self { Self() }
}
