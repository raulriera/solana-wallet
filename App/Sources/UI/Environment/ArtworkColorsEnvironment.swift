import SwiftUI

extension EnvironmentValues {
    /// The logo color sampler, or `nil` for the placeholder gray.
    @Entry var artworkColors: (any ArtworkColorProviding)? = nil
}
