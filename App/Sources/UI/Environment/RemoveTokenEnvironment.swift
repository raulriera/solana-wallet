import SwiftUI

extension EnvironmentValues {
    /// Removes a token from the window's list; `nil` outside the portfolio, where no token can be removed.
    @Entry var removeToken: TokenRemovalAction?
}
