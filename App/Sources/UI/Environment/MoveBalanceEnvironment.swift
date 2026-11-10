import SwiftUI

extension EnvironmentValues {
    /// The action that opens a move of a token between balances, or `nil` outside a token's details.
    @Entry var moveBalance: PrivateBalanceMoveAction?
}
