import Foundation
import Transactions

/// A format style that shortens an address to its first and last four characters, as in 6d8t…EmtK.
nonisolated struct AddressFormatStyle: FormatStyle {
    func format(_ address: Address) -> String {
        "\(address.value.prefix(4))…\(address.value.suffix(4))"
    }
}

nonisolated extension FormatStyle where Self == AddressFormatStyle {
    static var shortAddress: Self { Self() }
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
