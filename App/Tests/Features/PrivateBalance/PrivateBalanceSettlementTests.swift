import Privacy
import Testing
@testable import RPC
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceSettlementTests {
    @Test
    func `A move that can't be recorded changes nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()], failsSaving: true)
        let settlement = try await Self.settlement(of: PrivateBalanceFixtures.preparedDeposit(5_000, of: .nativeSOL, from: account),
                                                   notes: notes)

        await settlement.settle(PrivateBalanceFixtures.outcome(.succeeded(slot: 5)))

        #expect(await notes.value == [id: NoteSyncState()])
    }

    @MainActor
    private static func settlement(of transaction: PreparedPrivateTransaction,
                                   notes: StoredValue<PrivateBalances.Notes>) throws -> PrivateBalanceSettlement {
        let balances = PrivateBalances.inMemory(keys: StoredValue(), notes: notes,
                                                recovery: try PrivateBalanceFixtures.recoveryStore(),
                                                responses: HTTPResponses.privateNotes())
        return PrivateBalanceSettlement(balances: balances, transaction: transaction)
    }
}
