import SwiftUI
import Transactions

/// An action that removes a confirmed token from an account's list.
struct TokenRemovalAction {
    let removal: TokenRemovalModel

    /// Removes a token the person confirmed.
    ///
    /// - Parameter mint: The mint address of the token to remove.
    func callAsFunction(_ mint: Address) {
        removal.remove(mint)
    }
}
