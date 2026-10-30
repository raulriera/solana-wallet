import SwiftUI

extension EnvironmentValues {
    /// The action that opens a move of SOL between balances, or `nil` outside SOL's details.
    @Entry var moveBalance: PrivateBalanceMoveAction?
}
