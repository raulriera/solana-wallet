import SwiftUI

extension EnvironmentValues {
    /// Creates new accounts in saved wallets; `nil` where no account can be created, as in previews.
    @Entry var accountCreation: AccountCreation?
}
