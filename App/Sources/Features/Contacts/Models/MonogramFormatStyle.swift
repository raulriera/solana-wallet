import Foundation
import Transactions

/// A format style that abbreviates a recipient to its name's initials, as in AO for Adam Okon, or, when it has no name to
/// abbreviate, to its address's first two characters in uppercase, as in 6D for 6d8t…EmtK.
nonisolated struct MonogramFormatStyle: LocalizedFormatStyle {
    var locale: Locale = .autoupdatingCurrent

    func format(_ recipient: PaymentRecipient) -> String {
        let name = recipient.name.flatMap { try? PersonNameComponents($0) }
        return name?.formatted(.name(style: .abbreviated).locale(locale))
            ?? recipient.address.value.prefix(2).uppercased()
    }
}

nonisolated extension FormatStyle where Self == MonogramFormatStyle {
    /// A recipient's initials, or its address's first two characters when it has no name to abbreviate.
    static var monogram: Self { Self() }
}
