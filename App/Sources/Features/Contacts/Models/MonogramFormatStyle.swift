import Foundation
import Transactions

/// A format style that abbreviates a recipient to its name's initials and a trailing number of up to two digits, as in
/// AO for Adam Okon and A2 for Account 2, or, when it has no name to abbreviate, to its address's first two characters in uppercase, as in
/// 6D for 6d8t…EmtK.
nonisolated struct MonogramFormatStyle: LocalizedFormatStyle {
    var locale: Locale = .autoupdatingCurrent

    func format(_ recipient: PaymentRecipient) -> String {
        guard let name = recipient.name, let components = try? PersonNameComponents(name) else {
            return recipient.address.value.prefix(2).uppercased()
        }
        let lastWord = name.split(whereSeparator: \.isWhitespace).last ?? ""
        let number = lastWord.count <= 2 && lastWord.allSatisfy(\.isWholeNumber) ? lastWord : ""
        return components.formatted(.name(style: .abbreviated).locale(locale)) + number
    }
}

nonisolated extension FormatStyle where Self == MonogramFormatStyle {
    /// A recipient's initials and trailing number, or its address's first two characters when it has no name to
    /// abbreviate.
    static var monogram: Self { Self() }
}
