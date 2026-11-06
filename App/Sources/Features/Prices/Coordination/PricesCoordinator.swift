import Foundation
import Observation
import Storage

/// Coordinates one window's price provider choice and custom price servers.
@MainActor
@Observable
final class PricesCoordinator: PriceActions {
    /// The screens pushed above Prices.
    var path: [PricesRoute] = []
    /// The price server check of the last opened setup screen.
    private(set) var setup: ProviderSetupModel<CustomPriceError>?
    /// The custom price server whose details opened last.
    private(set) var details: URL?
    var error: PricesError?
    /// The ID of the waiting change.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Request?
    private let prices: PriceStore
    private let connection: any ProviderConnecting<CustomPriceError>

    /// A change that waits for storage.
    private enum Request {
        case select(PriceSettings.Provider)
        case remove(URL)

        /// The error to show when the change can't be saved.
        var error: PricesError {
            switch self {
            case .select: .settingsUnsaved
            case .remove: .deletionUnsaved
            }
        }
    }

    /// Creates a coordinator with the price services.
    ///
    /// - Parameters:
    ///   - prices: The price provider choice and custom price servers.
    ///   - connection: The connection that checks and adds a custom price server URL.
    init(prices: PriceStore, connection: any ProviderConnecting<CustomPriceError>) {
        self.prices = prices
        self.connection = connection
    }

    func select(_ provider: PriceSettings.Provider) {
        begin(.select(provider))
    }

    func showDetails(of url: URL) {
        guard attempt == nil else { return }
        details = url
        path.append(.serverDetails)
    }

    func addServer() {
        guard attempt == nil else { return }
        setup = ProviderSetupModel(connection: connection)
        path.append(.serverSetup)
    }

    func remove(_ url: URL) {
        begin(.remove(url))
    }

    /// Reads the price provider choice, and sets an error when it can't be read.
    func load() async {
        await prices.load()
        guard !Task.isCancelled, prices.phase == .unreadable else { return }
        error = .settingsUnreadable
    }

    /// Closes the screens pushed above Prices.
    func leave() {
        path = []
    }

    /// Runs the waiting change once.
    ///
    /// - Parameter attempt: The ID of the change to run.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { self.attempt = nil }
        do {
            switch request {
            case .select(let provider): try await prices.select(provider)
            case .remove(let url): try await prices.remove(url)
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error as? PricesError ?? request.error
        }
    }

    /// Accepts a change unless another one waits.
    ///
    /// - Parameter request: The change to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        self.request = request
        attempt = UUID()
    }
}
