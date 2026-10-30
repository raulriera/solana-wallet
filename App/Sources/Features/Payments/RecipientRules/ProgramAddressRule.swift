import Foundation
import Transactions

/// A rule that warns about an address that has no key, such as a program's address.
nonisolated struct ProgramAddressRule: RecipientRule {
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        address.isOnCurve ? nil : .offCurve
    }
}

nonisolated extension RecipientRule where Self == ProgramAddressRule {
    static var programAddress: Self { Self() }
}
