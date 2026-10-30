import SwiftUI

extension EnvironmentValues {
    /// Whether recovery words can show: the scene is active and not captured.
    var canDisplayRecovery: Bool { scenePhase == .active && !isSceneCaptured }
}
