import Foundation
import Observation
import Synchronization
import Testing
@testable import widgets

/// Verifies root replacement and observation through the window's routing contract.
@MainActor
struct WindowRouterTests {
    /// Replacing onboarding notifies consumers reading the protocol's destination.
    @Test
    func `Opening a saved wallet replaces onboarding and notifies its window`() throws {
        let router: any WindowRouting = WindowRouter(initialDestination: .onboarding)
        let account = try Account.fixture(index: 1)
        let changed = Mutex(false)
        #expect(router.destination == .onboarding)
        withObservationTracking {
            _ = router.destination
        } onChange: {
            changed.withLock { $0 = true }
        }

        router.route(to: .wallet(account))

        let notified = changed.withLock(\.self)
        #expect(router.destination == .wallet(account))
        #expect(notified)
    }

    /// Completing one window's setup leaves another window's draft flow in place.
    @Test
    func `Opening a saved wallet leaves another window in onboarding`() throws {
        let first: any WindowRouting = WindowRouter(initialDestination: .onboarding)
        let second: any WindowRouting = WindowRouter(initialDestination: .onboarding)

        first.route(to: .wallet(try .fixture(index: 1)))

        #expect(second.destination == .onboarding)
    }

    /// Windows showing the same account can select different accounts independently.
    @Test
    func `Changing wallets does not redirect or notify another window showing the same account`() throws {
        let original = try Account.fixture(index: 1)
        let replacement = try Account.fixture(index: 2)
        let first: any WindowRouting = WindowRouter(initialDestination: .wallet(original))
        let second: any WindowRouting = WindowRouter(initialDestination: .wallet(original))
        #expect(first.destination == .wallet(original))
        let changed = Mutex(false)
        withObservationTracking {
            _ = second.destination
        } onChange: {
            changed.withLock { $0 = true }
        }

        first.route(to: .wallet(replacement))

        let notified = changed.withLock(\.self)
        #expect(first.destination == .wallet(replacement))
        #expect(second.destination == .wallet(original))
        #expect(!notified)
    }
}
