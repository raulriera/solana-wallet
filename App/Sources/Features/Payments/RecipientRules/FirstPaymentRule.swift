import Foundation
import Transactions

/// Notes when the person hasn't paid an address before.
nonisolated struct FirstPaymentRule: RecipientRule {
    /// Looks the address up among the addresses the person paid.
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: ``RecipientWarning/firstPayment`` when the person never paid the address.
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        context.paidAddresses.contains(address) ? nil : .firstPayment
    }
}

nonisolated extension RecipientRule where Self == FirstPaymentRule {
    /// Notes an address the person hasn't paid before.
    static var firstPayment: Self { Self() }
}
