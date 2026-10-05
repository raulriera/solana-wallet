import SwiftUI

extension EnvironmentValues {
    /// Whether recovery words may appear: the scene is active, and nothing records or mirrors it.
    var canDisplayRecovery: Bool { scenePhase == .active && !isSceneCaptured }
}
