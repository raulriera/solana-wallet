import SwiftUI

extension EnvironmentValues {
    /// The action that opens the choice of who to send a private balance to, or `nil` outside a token's details.
    @Entry var sendPrivately: PrivateSendAction?
}
