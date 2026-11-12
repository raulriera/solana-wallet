import Foundation
import ModularArithmetic
import Testing
@testable import Privacy
@testable import RPC

struct NoteSyncStateSpendClaimsTests {
    @Test
    func `Claims that their transactions confirm prove the spent nullifiers`() async throws {
        let note = NoteFixtures.note(at: 1)
        let state = try Self.state(holding: [note])
        let transport = Self.transport(["spender": SpendTransactions.result(spending: [note.nullifier.bigEndianBytes])])
        var reads = SpendReads()

        let confirmed = try await state.confirmedSpends(in: [Self.claim("spender", of: [note])], reads: &reads,
                                                        using: SolanaRPC.devnet(transport: transport))

        #expect(confirmed.proven == [note.nullifier.bigEndianBytes])
        #expect(confirmed.rejected.isEmpty)
        #expect(confirmed.missingReads.isEmpty)
        #expect(reads.signatures == ["spender"])
    }

    @Test
    func `Claims whose transactions failed or spend other nullifiers are refuted`() async throws {
        let notes = [NoteFixtures.note(at: 1), NoteFixtures.note(at: 2)]
        let other = [UInt8](repeating: 9, count: 32)
        let transport = Self.transport([
            "failed": SpendTransactions.result(spending: [notes[0].nullifier.bigEndianBytes],
                                               error: SpendTransactions.failure),
            "unrelated": SpendTransactions.result(spending: [other]),
        ])
        var reads = SpendReads()

        let confirmed = try await Self.state(holding: notes).confirmedSpends(
            in: [Self.claim("failed", of: [notes[0]]), Self.claim("unrelated", of: [notes[1]], slot: 6)], reads: &reads,
            using: SolanaRPC.devnet(transport: transport)
        )

        #expect(confirmed.proven == [other])
        #expect(confirmed.rejected == ["failed", "unrelated"])
    }

    @Test
    func `Claims whose transactions aren't found count a missing read, and the tenth refutes them`() async throws {
        let notes = [NoteFixtures.note(at: 1), NoteFixtures.note(at: 2)]
        let state = try Self.state(holding: notes, missingReads: ["late": 9, "forgotten": 3])
        var reads = SpendReads()

        let confirmed = try await state.confirmedSpends(
            in: [Self.claim("new", of: [notes[0]]), Self.claim("late", of: [notes[1]], slot: 6)], reads: &reads,
            using: SolanaRPC.devnet(transport: Self.transport([:]))
        )

        #expect(confirmed.proven.isEmpty)
        #expect(confirmed.rejected == ["late"])
        #expect(confirmed.missingReads == ["new": 1])
    }

    @Test
    func `Refuted claims that a claim still names stay refuted without a read`() async throws {
        let note = NoteFixtures.note(at: 1)
        let state = try Self.state(holding: [note], rejected: ["named", "forgotten"])
        let transport = Self.transport([:])
        var reads = SpendReads()

        let confirmed = try await state.confirmedSpends(in: [Self.claim("named", of: [note])], reads: &reads,
                                                        using: SolanaRPC.devnet(transport: transport))

        #expect(confirmed.rejected == ["named"])
        #expect(reads.signatures.isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Claims that name no counted note aren't read`() async throws {
        let transport = Self.transport([:])
        var reads = SpendReads()

        let confirmed = try await Self.state(holding: [NoteFixtures.note(at: 1)]).confirmedSpends(
            in: [Self.claim("other", of: [NoteFixtures.note(at: 2)])], reads: &reads,
            using: SolanaRPC.devnet(transport: transport)
        )

        #expect(confirmed.proven.isEmpty)
        #expect(confirmed.rejected.isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    private static func state(
        holding notes: [ReceivedNote],
        rejected: Set<String> = [],
        missingReads: [String: Int] = [:]
    ) throws -> NoteSyncState {
        try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: nil, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: rejected, missingSpendReads: missingReads
        )
    }

    private static func claim(_ signature: String, of notes: [ReceivedNote], slot: UInt64 = 5) -> ShieldedTransaction {
        ShieldedTransaction(
            signature: signature, slot: slot, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: notes.map(\.nullifier.bigEndianBytes), isProofless: false
        )
    }

    private static func transport(_ transactions: [String: String]) -> StubTransport {
        StubTransport { request in
            let signature = try #require((try requestBody(request)["params"] as? [Any])?.first as? String)
            return try reply(to: request, payload: #""result":\#(transactions[signature] ?? "null")"#)
        }
    }
}
