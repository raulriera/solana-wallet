import Foundation
import Transactions

/// A list of rules that check a recipient's address.
nonisolated struct RecipientClassifier: Sendable {
    /// The rules, most serious first.
    let rules: [any RecipientRule]

    /// Runs every rule over an address.
    ///
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: The warnings of the rules that didn't pass, in rule order.
    func warnings(for address: Address, in context: RecipientContext) -> [RecipientWarning] {
        rules.compactMap { $0.warning(for: address, in: context) }
    }
}

nonisolated extension RecipientClassifier {
    /// The rules shown while a recipient is entered.
    static let entry = RecipientClassifier(rules: [.lookAlike, .programAddress])
    /// The rules shown on a payment's review.
    static let review = RecipientClassifier(rules: [.lookAlike, .programAddress, .firstPayment])
}
