import Foundation
import Transactions

/// Warns when an address starts and ends like a different address the person used, as address poisoning arranges.
nonisolated struct LookAlikeRule: RecipientRule {
    /// Compares the address's shortened form, as people see it, with every other known address.
    /// - Parameters:
    ///   - address: The address to pay.
    ///   - context: The person's own history.
    /// - Returns: ``RecipientWarning/lookAlike`` when another known address shortens the same way.
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        let shortened = address.formatted(.shortAddress)
        let isLookAlike = context.knownAddresses.contains { $0 != address && $0.formatted(.shortAddress) == shortened }
        return isLookAlike ? .lookAlike : nil
    }
}

nonisolated extension RecipientRule where Self == LookAlikeRule {
    /// Warns about an address that starts and ends like a different one the person used.
    static var lookAlike: Self { Self() }
}
