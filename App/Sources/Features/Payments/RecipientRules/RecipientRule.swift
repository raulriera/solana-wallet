import Foundation
import Transactions

/// The person's own history that rules check a recipient against.
nonisolated struct RecipientContext: Sendable {
    /// The person's accounts, contacts, and paid addresses.
    let knownAddresses: [Address]
    let paidAddresses: Set<Address>
}

/// A check of a recipient before paying them.
nonisolated protocol RecipientRule: Sendable {
    /// Checks an address.
    ///
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: The warning, or `nil` when the check passes.
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning?
}
