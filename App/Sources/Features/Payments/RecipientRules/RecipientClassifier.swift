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
