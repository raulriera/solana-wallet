import SwiftUI

extension EnvironmentValues {
    /// The action that removes a token from the list, or `nil` outside the portfolio.
    @Entry var removeToken: TokenRemovalAction?
}
