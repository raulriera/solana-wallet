import Foundation
import Transactions

/// A rule that warns about an address that starts and ends like a different address the person used.
nonisolated struct LookAlikeRule: RecipientRule {
    func warning(for address: Address, in context: RecipientContext) -> RecipientWarning? {
        let shortened = address.formatted(.shortAddress)
        let isLookAlike = context.knownAddresses.contains { $0 != address && $0.formatted(.shortAddress) == shortened }
        return isLookAlike ? .lookAlike : nil
    }
}

nonisolated extension RecipientRule where Self == LookAlikeRule {
    static var lookAlike: Self { Self() }
}
