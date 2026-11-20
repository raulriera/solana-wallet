import Foundation
import RPC
import Storage
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RecentPaymentStoreTests {
    @Test
    func `A payment is listed first in place of the earlier payment to its address`() async throws {
        let store = RecentPaymentStore.inMemory()
        let alice = RecentPayment.fixture(to: ContactsFixtures.alice, at: 1_000)
        let bruno = RecentPayment.fixture(to: ContactsFixtures.bruno, at: 2_000)
        let aliceAgain = RecentPayment.fixture(to: ContactsFixtures.alice, at: 3_000)

        try await store.add(alice, on: .mainnet)
        try await store.add(bruno, on: .mainnet)
        try await store.add(aliceAgain, on: .mainnet)

        #expect(store.payments(on: .mainnet) == [aliceAgain, bruno])
    }

    @Test
    func `Only the latest 10 payments are kept`() async throws {
        let store = RecentPaymentStore.inMemory()
        let payments = try "23456789ABC".enumerated().map { index, digit in
            RecentPayment.fixture(to: try Address(String(repeating: "1", count: 31) + String(digit)), at: TimeInterval(index))
        }

        for payment in payments { try await store.add(payment, on: .mainnet) }

        #expect(store.payments(on: .mainnet) == Array(payments.reversed().prefix(10)))
    }

    @Test
    func `A saved payment keeps its facts under their permanent names beside version 1`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecentPaymentStore(directory: directory)

        try await store.add(RecentPayment.fixture(to: ContactsFixtures.alice, at: 800_000_000), on: .devnet)

        let saved = try Data(contentsOf: directory.appending(path: "payments.json"))
        #expect(try saved.jsonObject() == Data("""
            {"version": 1, "value": {"devnet": [{"address": "\(ContactsFixtures.alice.value)", "date": 800000000}]}}
            """.utf8).jsonObject())
    }

    @Test
    func `Each network's payments are read back after a relaunch`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecentPaymentStore(directory: directory)
        let alice = RecentPayment.fixture(to: ContactsFixtures.alice, at: 1_000)
        let bruno = RecentPayment.fixture(to: ContactsFixtures.bruno, at: 2_000)

        try await store.add(alice, on: .mainnet)
        try await store.add(bruno, on: .devnet)

        let relaunched = RecentPaymentStore(directory: directory)
        #expect(relaunched.phase == .unloaded)
        await relaunched.load()
        #expect(relaunched.payments(on: .mainnet) == [alice])
        #expect(relaunched.payments(on: .devnet) == [bruno])
    }
}
