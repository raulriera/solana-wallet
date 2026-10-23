import Foundation
import Transactions

/// Runs a screen's rules over an address, in the order the screen lists them.
nonisolated struct RecipientClassifier: Sendable {
    /// The checks to run, most serious first.
    let rules: [any RecipientRule]

    /// Runs every rule over an address.
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: The warnings of the rules that didn't pass, in rule order.
    func warnings(for address: Address, in context: RecipientContext) -> [RecipientWarning] {
        rules.compactMap { $0.warning(for: address, in: context) }
    }
}

nonisolated extension RecipientClassifier {
    /// The checks shown while a recipient is entered: whether the payment could go somewhere unintended.
    static let entry = RecipientClassifier(rules: [.lookAlike, .programAddress])
    /// The checks shown on a payment's review: the entry's, and whether the person paid the address before.
    static let review = RecipientClassifier(rules: [.lookAlike, .programAddress, .firstPayment])
}
