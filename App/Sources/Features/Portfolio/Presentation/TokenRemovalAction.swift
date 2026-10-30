import Portfolio
import SwiftUI

/// An action that removes a confirmed token from an account's list.
struct TokenRemovalAction {
    let removal: TokenRemovalModel

    /// Removes a token the person confirmed.
    ///
    /// - Parameter token: The token to remove.
    func callAsFunction(_ token: Holding.Identity) {
        removal.remove(token)
    }
}
