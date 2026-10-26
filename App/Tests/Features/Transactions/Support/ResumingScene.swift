import Observation
import SwiftUI
@testable import widgets

/// Holds the scene phase that a hosted window reports and the shared provider changes, so a test can activate the
/// scene or connect through another provider.
@MainActor
@Observable
final class ResumingScene {
    /// The scene phase that the hosted window reports.
    var phase: ScenePhase
    /// The shared counts of provider changes.
    @ObservationIgnored let providerRevisions = ProviderRevisions()

    /// Starts the hosted window in a scene phase.
    /// - Parameter phase: The scene phase that the window reports first.
    init(_ phase: ScenePhase) {
        self.phase = phase
    }
}
