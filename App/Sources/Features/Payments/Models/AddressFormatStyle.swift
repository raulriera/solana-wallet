import Foundation
import Transactions

/// A format style that shortens an address to its first and last four characters, as in 6d8t…EmtK, or abbreviates it
/// to its first two characters in uppercase, as in 6D.
nonisolated struct AddressFormatStyle: FormatStyle {
    /// How much of an address a format style shows.
    enum Style: Codable, Hashable, Sendable {
        /// The first and last four characters, as in 6d8t…EmtK.
        case short
        /// The first two characters in uppercase, as in 6D.
        case abbreviated
    }

    var style: Style

    func format(_ address: Address) -> String {
        switch style {
        case .short: "\(address.value.prefix(4))…\(address.value.suffix(4))"
        case .abbreviated: address.value.prefix(2).uppercased()
        }
    }
}

nonisolated extension FormatStyle where Self == AddressFormatStyle {
    static var shortAddress: Self { Self(style: .short) }

    /// An address's first two characters in uppercase.
    static var monogram: Self { Self(style: .abbreviated) }
}

extension Address {
    /// Formats the address with a format style, such as ``AddressFormatStyle``.
    ///
    /// - Parameter style: The format style.
    /// - Returns: The formatted address.
    nonisolated func formatted<Style: FormatStyle>(_ style: Style) -> Style.FormatOutput
    where Style.FormatInput == Address {
        style.format(self)
    }
}
