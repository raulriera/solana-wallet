import Encoding
import Foundation
import Transactions
import Wallet
@testable import widgets

extension widgets.Account {
    /// Creates public account metadata without generating or accessing recovery material.
    /// - Parameters:
    ///   - index: A small index used to generate a distinct public address and path.
    ///   - recoveryID: The wallet's recovery identity, a new one by default.
    /// - Returns: A public test account.
    /// - Throws: An address validation error.
    static func fixture(index: UInt8, recoveryID: UUID = UUID()) throws -> widgets.Account {
        Account(id: UUID(), recoveryID: recoveryID,
            address: try Address(Base58.encode(Array(repeating: index, count: 32))), path: .solana(account: UInt32(index)))
    }

    /// The published wallet's first account, for tests that read or edit its token list without its recovery.
    /// - Returns: Public account metadata at ``PublicWallet/address``.
    /// - Throws: An address validation error.
    static func publicWallet() throws -> widgets.Account {
        Account(id: UUID(), recoveryID: UUID(), address: try Address(PublicWallet.address), path: .solana(account: 0))
    }
}
