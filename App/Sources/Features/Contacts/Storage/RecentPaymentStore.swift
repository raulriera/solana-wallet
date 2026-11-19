import Algorithms
import Foundation
import Observation
import RPC
import Storage

/// A store that keeps the latest payment to each address on each network.
@MainActor
@Observable
final class RecentPaymentStore: Erasable {
    /// The most payments kept for each network.
    nonisolated static let limit = 10

    private let lists: PersistentValue<[Network: [RecentPayment]]>

    /// Creates a store without reading the payments.
    ///
    /// - Parameter storage: The storage that keeps each network's payments.
    init(storage: any ValueStoring<[Network: [RecentPayment]]>) {
        lists = PersistentValue(storage: storage, empty: [:])
    }

    /// Creates a store of the payments file in a directory without reading it.
    ///
    /// - Parameter directory: The directory of the file.
    convenience init(directory: URL) {
        self.init(storage: FileItem(url: directory.appending(path: "payments.json"),
                                    coding: .json([Network: [RecentPayment]].self, version: 1, outdated: [:])))
    }

    var phase: PersistentValuePhase { lists.phase }

    /// Reads the payments, unless they were already read.
    func load() async {
        await lists.load()
    }

    /// Returns the latest payment to each address on a network.
    ///
    /// - Parameter network: The network of the payments.
    /// - Returns: At most ``limit`` payments, newest first, or none before they're read.
    func payments(on network: Network) -> [RecentPayment] {
        lists.value[network, default: []]
    }

    /// Saves a payment as the newest on a network, in place of the earlier payment to its address, and drops the
    /// oldest beyond the limit.
    ///
    /// - Parameters:
    ///   - payment: The payment that landed.
    ///   - network: The network of the payment.
    /// - Throws: A storage error.
    func add(_ payment: RecentPayment, on network: Network) async throws {
        try await lists.update { lists in
            let payments = [payment] + lists[network, default: []]
            lists[network] = Array(payments.uniqued(on: \.address).prefix(Self.limit))
        }
    }

    func erase() async throws {
        try await lists.erase()
    }
}
