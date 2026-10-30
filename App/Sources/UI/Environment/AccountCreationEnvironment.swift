import SwiftUI

extension EnvironmentValues {
    /// The action that creates accounts, or `nil` where none can be created.
    @Entry var accountCreation: AccountCreation?
}
