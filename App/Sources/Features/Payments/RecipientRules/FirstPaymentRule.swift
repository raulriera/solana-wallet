import Foundation
import Transactions

/// A rule that notes an address the person hasn't paid before.
nonisolated struct FirstPaymentRule: RecipientRule {
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        context.paidAddresses.contains(address) ? nil : .firstPayment
    }
}

nonisolated extension RecipientRule where Self == FirstPaymentRule {
    static var firstPayment: Self { Self() }
}
