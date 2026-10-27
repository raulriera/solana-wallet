import Foundation
import Observation
import RPC
import Storage

/// Owns the Currency screens' changes to the choice that every window shares: one change at a time, and why one
/// failed.
@MainActor
@Observable
final class CurrencySettingsModel {
    /// An error for the alert.
    var error: CurrencyError?
    /// The change waiting for the screen's task.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Request?

    /// A change that waits for storage.
    private enum Request {
        case source(CurrencySettings.RateSource?)
        case currency(String?)
    }

    /// Chooses the rate source; taps while another change waits are ignored.
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    func select(_ source: CurrencySettings.RateSource?) {
        begin(.source(source))
    }

    /// Chooses the currency; taps while another change waits are ignored.
    /// - Parameter code: The ISO code of the currency, or `nil` to follow the device's region.
    func select(currencyCode code: String?) {
        begin(.currency(code))
    }

    /// Reads the choice that every window shares, unless it was already read; an unreadable choice explains the
    /// failure.
    /// - Parameter store: The choice that every window shares.
    func load(from store: CurrencyStore) async {
        await store.load()
        guard !Task.isCancelled, store.phase == .unreadable else { return }
        error = .settingsUnreadable
    }

    /// Runs the waiting change once in the screen's SwiftUI-managed task; the change reaches every window through the
    /// store.
    /// - Parameters:
    ///   - attempt: The identifier the screen's task captured.
    ///   - store: The choice that every window shares.
    func run(_ attempt: UUID?, with store: CurrencyStore) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .source(let source): try await store.select(source)
            case .currency(let code): try await store.select(currencyCode: code)
            }
        } catch is CancellationError {
            // The screen left before the change was saved.
        } catch is RPCError {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            error = .ratesUnavailable
        } catch let error as CurrencyError {
            // A choice that can't be read explains the read.
            guard !Task.isCancelled, self.attempt == attempt else { return }
            self.error = error
        } catch {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            self.error = .settingsUnsaved
        }
    }

    /// Accepts one change at a time, ignoring taps while another change waits.
    /// - Parameter request: The change to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        self.request = request
        attempt = UUID()
    }
}
