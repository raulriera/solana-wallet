import SwiftUI

extension EnvironmentValues {
    /// The shared logo color sampler, or `nil` where cards keep the window's surface color.
    @Entry var artworkColors: (any ArtworkColorProviding)? = nil
}
