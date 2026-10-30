import Observation
import SwiftUI
@testable import widgets

@MainActor
@Observable
final class ResumingScene {
    var phase: ScenePhase
    @ObservationIgnored let providers = ProviderStore.inMemory(key: StoredValue("fixture-key"))

    init(_ phase: ScenePhase) {
        self.phase = phase
    }
}
