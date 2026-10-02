import Foundation
import Observation
import Synchronization
import Testing
@testable import widgets

/// Verifies root replacement and observation through the window's routing contract.
@MainActor
struct WindowRouterTests {
    /// Replacing onboarding notifies consumers reading the protocol's destination.
    @Test("opening a saved wallet replaces onboarding and notifies its window")
    func openingWalletReplacesOnboarding() {
        let router: any WindowRouting = WindowRouter(initialDestination: .onboarding)
        let accountID = UUID()
        let changed = Mutex(false)
        #expect(router.destination == .onboarding)
        withObservationTracking {
            _ = router.destination
        } onChange: {
            changed.withLock { $0 = true }
        }

        router.route(to: .wallet(accountID: accountID))

        let notified = changed.withLock(\.self)
        #expect(router.destination == .wallet(accountID: accountID))
        #expect(notified)
    }

    /// Completing one window's setup leaves another window's draft flow in place.
    @Test("opening a saved wallet leaves another window in onboarding")
    func openingWalletPreservesOtherWindowOnboarding() {
        let first: any WindowRouting = WindowRouter(initialDestination: .onboarding)
        let second: any WindowRouting = WindowRouter(initialDestination: .onboarding)

        first.route(to: .wallet(accountID: UUID()))

        #expect(second.destination == .onboarding)
    }

    /// Windows showing the same account can select different accounts independently.
    @Test("changing wallets does not redirect or notify another window showing the same account")
    func changingWalletPreservesOtherWindowSelection() {
        let originalID = UUID()
        let replacementID = UUID()
        let first: any WindowRouting = WindowRouter(initialDestination: .wallet(accountID: originalID))
        let second: any WindowRouting = WindowRouter(initialDestination: .wallet(accountID: originalID))
        #expect(first.destination == .wallet(accountID: originalID))
        let changed = Mutex(false)
        withObservationTracking {
            _ = second.destination
        } onChange: {
            changed.withLock { $0 = true }
        }

        first.route(to: .wallet(accountID: replacementID))

        let notified = changed.withLock(\.self)
        #expect(first.destination == .wallet(accountID: replacementID))
        #expect(second.destination == .wallet(accountID: originalID))
        #expect(!notified)
    }
}
