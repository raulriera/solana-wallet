import Foundation
import Observation
import RPC
import Storage

/// Runs the Currency screens' changes to the currency choice, one at a time.
@MainActor
@Observable
final class CurrencySettingsModel {
    var error: CurrencyError?
    /// The identifier of the waiting change, or `nil` when none waits.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Request?

    /// A change to the currency choice.
    private enum Request {
        case source(CurrencySettings.RateSource?)
        case currency(String?)
    }

    /// Chooses the rate source.
    ///
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    func select(_ source: CurrencySettings.RateSource?) {
        begin(.source(source))
    }

    /// Chooses the currency.
    ///
    /// - Parameter code: The currency's ISO code, or `nil` to follow the device's region.
    func select(currencyCode code: String?) {
        begin(.currency(code))
    }

    /// Loads the currency choice unless it's already loaded.
    ///
    /// - Parameter store: The currency store.
    func load(from store: CurrencyStore) async {
        await store.load()
        guard !Task.isCancelled, store.phase == .unreadable else { return }
        error = .settingsUnreadable
    }

    /// Runs the waiting change.
    ///
    /// - Parameters:
    ///   - attempt: The identifier of the change to run.
    ///   - store: The currency store.
    func run(_ attempt: UUID?, with store: CurrencyStore) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .source(let source): try await store.select(source)
            case .currency(let code): try await store.select(currencyCode: code)
            }
        } catch is CancellationError {
        } catch is RPCError {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            error = .ratesUnavailable
        } catch let error as CurrencyError {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            self.error = error
        } catch {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            self.error = .settingsUnsaved
        }
    }

    /// Starts a change unless another change waits.
    ///
    /// - Parameter request: The change to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        self.request = request
        attempt = UUID()
    }
}
