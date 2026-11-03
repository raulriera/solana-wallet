import Encoding
import Foundation
import Transactions
import Wallet
@testable import widgets

extension widgets.Account {
    static let fixtureRecoveryID = UUID()

    static func fixture(index: UInt8, recoveryID: UUID = fixtureRecoveryID) throws -> widgets.Account {
        Account(id: UUID(), recoveryID: recoveryID,
            address: try Address(Base58.encode(Array(repeating: index, count: 32))), path: .solana(account: UInt32(index)))
    }

    static func publicWallet() throws -> widgets.Account {
        Account(id: UUID(), recoveryID: UUID(), address: try Address(PublicWallet.address), path: .solana(account: 0))
    }
}
