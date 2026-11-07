import Storage
import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PricesLifecycleTests {
    @Test
    func `An unreadable choice shows its alert`() async throws {
        let coordinator = PricesCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))
        let hosted = try HostedWindow(Color.clear.modifier(PricesLifecycle(coordinator: coordinator)))
        defer { hosted.close() }

        #expect(try await hosted.presentsViewController())
        #expect(coordinator.error == .settingsUnreadable)
    }

    @Test
    func `A choice that can't be saved shows its alert`() async throws {
        let prices = PriceStore.inMemory(StoredValue(PriceSettings(), failsSaving: true))
        let coordinator = PricesCoordinator.inMemory(prices)
        let hosted = try HostedWindow(Color.clear.modifier(PricesLifecycle(coordinator: coordinator)))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        coordinator.select(.off)

        #expect(try await hosted.presentsViewController())
        #expect(coordinator.error == .settingsUnsaved)
    }
}
