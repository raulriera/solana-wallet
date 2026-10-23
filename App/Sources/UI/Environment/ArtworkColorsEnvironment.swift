import SwiftUI

extension EnvironmentValues {
    /// The shared logo color sampler, or `nil` where cards keep the placeholder gray.
    @Entry var artworkColors: (any ArtworkColorProviding)? = nil
}
