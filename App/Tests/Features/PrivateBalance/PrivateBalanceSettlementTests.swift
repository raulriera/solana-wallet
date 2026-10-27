import Privacy
@testable import RPC
import Testing
@testable import widgets

/// Verifies that a settled private move completes the account's private balance through the real private balances,
/// with local responses and in-memory notes.
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceSettlementTests {
    /// A succeeded deposit stays pending in the account's saved notes until the indexer reports it.
    @Test
    func `A succeeded deposit is recorded as pending`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let settlement = try await Self.settlement(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account),
                                                   notes: notes)

        await settlement.settle(PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(await notes.value?[id]?.pendingLamports == 5_000)
    }

    /// A move that can't be recorded is left for the indexer's next read, without an error.
    @Test
    func `A move that can't be recorded changes nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()], failsSaving: true)
        let settlement = try await Self.settlement(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account),
                                                   notes: notes)

        await settlement.settle(PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(await notes.value == [id: NoteSyncState()])
    }

    /// Creates the settlement of a move over in-memory private balances.
    /// - Parameters:
    ///   - transaction: The prepared move.
    ///   - notes: The saved private notes.
    /// - Returns: The settlement.
    /// - Throws: A fixture error.
    @MainActor
    private static func settlement(of transaction: PreparedPrivateTransaction,
                                   notes: StoredValue<PrivateBalances.Notes>) throws -> PrivateBalanceSettlement {
        let balances = PrivateBalances.inMemory(keys: StoredValue(), notes: notes,
                                                recovery: try PrivateBalanceFixtures.recoveryStore(),
                                                responses: HTTPResponses.privateNotes())
        return PrivateBalanceSettlement(balances: balances, transaction: transaction)
    }
}
