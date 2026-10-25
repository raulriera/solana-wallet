import Foundation
import Observation
import RPC

/// Owns the Currency screen's choice: the saved rate source and currency as last read, and each change.
@MainActor
@Observable
final class CurrencySettingsModel {
    /// The choice as last read, or `nil` before the first read, so no choice shows as selected.
    private(set) var settings: CurrencySettings?
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

    /// Reads the saved choice; an unreadable choice keeps the last one read and explains the failure.
    /// - Parameter selection: The choice that every window shares.
    func reload(from selection: CurrencySelection) async {
        do {
            let settings = try await selection.settings()
            guard !Task.isCancelled else { return }
            self.settings = settings
        } catch is CancellationError {
            // The screen left before the choice was read.
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .settingsUnreadable
        }
    }

    /// Runs the waiting change once in the screen's SwiftUI-managed task; the saved change reaches every window
    /// through the selection's revision.
    /// - Parameters:
    ///   - attempt: The identifier the screen's task captured.
    ///   - selection: The choice that every window shares.
    func run(_ attempt: UUID?, with selection: CurrencySelection) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .source(let source): try await selection.select(source)
            case .currency(let code): try await selection.select(currencyCode: code)
            }
        } catch is CancellationError {
            // The screen left before the change was saved.
        } catch is RPCError {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            error = .ratesUnavailable
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
