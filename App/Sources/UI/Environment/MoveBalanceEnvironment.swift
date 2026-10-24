import SwiftUI

extension EnvironmentValues {
    /// Opens a move of SOL between the account's balances; `nil` outside SOL's details, where no move can open.
    @Entry var moveBalance: PrivateBalanceMoveAction?
}
