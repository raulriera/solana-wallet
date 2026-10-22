import Foundation
import Transactions

/// What rules can see about the person's own history when they check a recipient.
nonisolated struct RecipientContext: Sendable {
    /// Addresses the person used: their accounts, contacts, and addresses they paid.
    let knownAddresses: [Address]
}

/// One thing to check about a recipient before paying them.
///
/// Add a check as its own rule type with a static shortcut, such as ``LookAlikeRule`` and `.lookAlike`, and list it in
/// the ``RecipientClassifier`` of each screen that should show it.
nonisolated protocol RecipientRule: Sendable {
    /// Checks an address.
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: The warning, or `nil` when the check passes.
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning?
}
