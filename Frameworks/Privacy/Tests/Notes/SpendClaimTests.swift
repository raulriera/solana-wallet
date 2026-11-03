import Testing
@testable import Privacy
@testable import RPC

struct SpendClaimTests {
    @Test
    func `Claims name each transaction once with its counted nullifiers, oldest first`() {
        let transactions = [
            Self.transaction("later", slot: 30, spending: [1, 5]),
            Self.transaction("earlier", slot: 20, spending: [2]),
            Self.transaction("later", slot: 25, spending: [3]),
            Self.transaction("uncounted", slot: 10, spending: [6]),
        ]

        let claims = SpendClaim.claims(in: transactions, of: Self.nullifiers(1, 2, 3))

        #expect(claims == [
            SpendClaim(signature: "earlier", slot: 20, nullifiers: Self.nullifiers(2)),
            SpendClaim(signature: "later", slot: 25, nullifiers: Self.nullifiers(1, 3)),
        ])
    }

    @Test
    func `Unread claims skip read, skipped, and covered claims`() {
        var reads = SpendReads()
        reads.record([SpendClaim(signature: "read", slot: 1, nullifiers: Self.nullifiers(1))])
        let claims = [
            SpendClaim(signature: "read", slot: 1, nullifiers: Self.nullifiers(1)),
            SpendClaim(signature: "covered", slot: 2, nullifiers: Self.nullifiers(1)),
            SpendClaim(signature: "skipped", slot: 3, nullifiers: Self.nullifiers(2)),
            SpendClaim(signature: "first", slot: 4, nullifiers: Self.nullifiers(2)),
            SpendClaim(signature: "repeated", slot: 5, nullifiers: Self.nullifiers(2)),
            SpendClaim(signature: "second", slot: 6, nullifiers: Self.nullifiers(2, 3)),
        ]

        let unread = claims.unread(by: reads, skipping: ["skipped"], limit: 8)

        #expect(unread.map(\.signature) == ["first", "second"])
    }

    @Test
    func `Unread claims stop once the sync has read the limit`() {
        var reads = SpendReads()
        reads.record([SpendClaim(signature: "read", slot: 1, nullifiers: Self.nullifiers(1))])
        let claims = (2...5).map {
            SpendClaim(signature: "claim \($0)", slot: UInt64($0), nullifiers: Self.nullifiers(UInt8($0)))
        }

        let unread = claims.unread(by: reads, skipping: [], limit: 3)

        #expect(unread.map(\.signature) == ["claim 2", "claim 3"])
    }

    @Test
    func `Reads gather the signatures and nullifiers of recorded claims`() {
        var reads = SpendReads()

        reads.record([
            SpendClaim(signature: "first", slot: 1, nullifiers: Self.nullifiers(1)),
            SpendClaim(signature: "second", slot: 2, nullifiers: Self.nullifiers(1, 2)),
        ])

        #expect(reads.signatures == ["first", "second"])
        #expect(reads.nullifiers == Self.nullifiers(1, 2))
    }

    private static func nullifiers(_ values: UInt8...) -> Set<[UInt8]> {
        Set(values.map { [UInt8](repeating: $0, count: 32) })
    }

    private static func transaction(_ signature: String, slot: UInt64, spending values: [UInt8])
        -> ShieldedTransaction {
        ShieldedTransaction(
            signature: signature, slot: slot, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: values.map { [UInt8](repeating: $0, count: 32) }, isProofless: false
        )
    }
}
