import Encoding
import Foundation
import Transactions
import Wallet
@testable import widgets

extension widgets.Account {
    /// Creates public account metadata.
    /// - Parameter index: A small index used to generate a distinct public address and path.
    /// - Returns: A public test account.
    /// - Throws: An address or derivation-path validation error.
    static func fixture(index: UInt8) throws -> widgets.Account {
        Account(id: UUID(), recoveryID: UUID(),
            address: try Address(Base58.encode(Array(repeating: index, count: 32))), path: try DerivationPath("m/44'/501'/\(index)'/0'"))
    }
}
