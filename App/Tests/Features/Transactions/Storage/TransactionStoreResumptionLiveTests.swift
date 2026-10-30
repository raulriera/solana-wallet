import Foundation
import Observation
import RPC
import Storage
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.tags(.network), .timeLimit(.minutes(3)))
struct TransactionStoreResumptionLiveTests {
    private static let lamports: UInt64 = 1_000_000

    @Test
    func `A devnet payment that a relaunch interrupted settles through resume`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wallets = try await DevnetWallets.configured()
        let rpcs = try LiveClients.devnetRPCs()
        let balance = try await rpcs[0].send(GetMultipleAccounts(addresses: [wallets.sender.address.value]))
        try #require((balance.value.first ?? nil)?.lamports ?? 0 >= Self.lamports + 10_000_000,
                     "Account 0 of DEVNET_TEST_SEED needs at least 0.011 devnet SOL")
        let coordinator = try TransactionCoordinator(rpc: rpcs[0],
                                                     store: SigningRecoveryStore(recovery: wallets.recovery), rpcs: rpcs)
        let simulation = try await coordinator.transfer(Self.lamports, using: wallets.sender,
                                                        to: wallets.recipient.address)
        try #require(simulation.diagnostics.value.error == nil)
        let record = TransactionRecord(.payment(recipient: wallets.recipient.address, mint: nil, units: Self.lamports),
                                       from: wallets.sender.id, submission: try await coordinator.submit(simulation),
                                       created: .now)
        let records = TransactionStore.files(in: directory)(record.key)
        let pending = TransactionStore.pendingIndex(in: directory)
        try await pending.save([record.key])
        try await records.save([record])

        let relaunched = TransactionStore(directory: directory) { _ in coordinator }
        await relaunched.resume()

        for await count in Observations({ relaunched.settledCount(for: record.key) }) where count == 1 { break }
        #expect(relaunched.record(record.id, for: record.key)?.status == .succeeded)
        #expect(try await records.load()?.first { $0.id == record.id }?.status == .succeeded)
        #expect(try await pending.load() == [])
    }
}
