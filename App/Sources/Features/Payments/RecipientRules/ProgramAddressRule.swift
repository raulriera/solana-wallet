import Foundation
import Transactions

/// Warns when no key exists for an address, so only the program that derived it can move what it receives.
nonisolated struct ProgramAddressRule: RecipientRule {
    /// Checks whether the address is off the Ed25519 curve, as program-derived addresses are.
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history, which this rule doesn't need.
    /// - Returns: ``RecipientWarning/offCurve`` when no key exists for the address.
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        address.isOnCurve ? nil : .offCurve
    }
}

nonisolated extension RecipientRule where Self == ProgramAddressRule {
    /// Warns about an address that belongs to a program, not a person.
    static var programAddress: Self { Self() }
}
