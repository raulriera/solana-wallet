import Foundation
import Testing
import RPC

/// Verifies the checks and redaction of transfer proof requests.
struct TransferProofRequestTests {
    private typealias Fixture = ProofFixtures

    /// Verifies the request's shape comes from the witness.
    ///
    /// - Throws: A validation error, which the fixture doesn't produce.
    @Test
    func `The shape counts the witness's slots`() throws {
        let request = try Fixture.request()

        #expect(request.inputCount == 1)
        #expect(request.outputCount == 2)
    }

    /// Verifies requests whose parts disagree are refused.
    ///
    /// - Parameters:
    ///   - trees: The number of trees to list.
    ///   - lookups: Each lookup's tree slot.
    ///   - publicInputs: The number of public inputs.
    ///   - error: The expected refusal.
    /// - Throws: A failed test prerequisite.
    @Test(arguments: [
        (0, [UInt8(0)], 17, TransferProofRequest.ValidationError.invalidCount),
        (3, [0], 17, .invalidCount),
        (1, [], 17, .invalidCount),
        (1, [0], 16, .invalidCount),
        (1, [1], 17, .invalidTreeSlot),
        (2, [1], 17, .invalidTreeSlot),
    ])
    func `Requests whose parts disagree are refused`(
        trees: Int, lookups: [UInt8], publicInputs: Int, error: TransferProofRequest.ValidationError
    ) throws {
        let tree = try TransferProofRequest.Tree(address: Fixture.tree, id: 0)
        let inputs = try lookups.map { try TransferProofRequest.Input(treeSlot: $0, commitment: nil, nullifier: nil) }
        let witness = try Fixture.witness()

        #expect(throws: error) {
            try TransferProofRequest(trees: Array(repeating: tree, count: trees), inputs: inputs,
                                     publicInputs: Array(repeating: Fixture.field(1), count: publicInputs),
                                     minContextSlot: nil, witness: witness)
        }
    }

    /// Verifies a public input of another length is refused.
    ///
    /// - Throws: A failed test prerequisite.
    @Test
    func `Public inputs must be field elements`() throws {
        let request = try Fixture.request()

        #expect(throws: TransferProofRequest.ValidationError.invalidLength) {
            try TransferProofRequest(trees: request.trees, inputs: request.inputs,
                                     publicInputs: Array(repeating: [1], count: 17), minContextSlot: nil,
                                     witness: request.witness)
        }
    }

    /// Verifies tree addresses and lookup values are checked.
    ///
    /// - Parameter make: Creates a part with an invalid value.
    @Test(arguments: [
        { _ = try TransferProofRequest.Tree(address: "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC", id: 0) },
        { _ = try TransferProofRequest.Tree(address: "0" + String(repeating: "1", count: 31), id: 0) },
    ] as [@Sendable () throws -> Void])
    func `Tree addresses must be 32 bytes of base 58`(make: @Sendable () throws -> Void) {
        #expect(throws: TransferProofRequest.ValidationError.invalidAddress) { try make() }
    }

    /// Verifies lookup values must be 32 bytes.
    ///
    /// - Parameters:
    ///   - commitment: The commitment, or `nil`.
    ///   - nullifier: The nullifier, or `nil`.
    @Test(arguments: [([UInt8]?([UInt8](repeating: 1, count: 31)), [UInt8]?.none), (nil, [UInt8](repeating: 1, count: 33))])
    func `Lookup values must be 32 bytes`(commitment: [UInt8]?, nullifier: [UInt8]?) {
        #expect(throws: TransferProofRequest.ValidationError.invalidLength) {
            try TransferProofRequest.Input(treeSlot: 0, commitment: commitment, nullifier: nullifier)
        }
    }

    /// Verifies descriptions, debug descriptions, and dumps reveal none of the witness's values.
    ///
    /// The fixture's secrets end in bytes `a1`, `b1`, `c1`, and `d1`, whose decimal and hexadecimal forms
    /// would appear in a reflected array.
    /// - Throws: A validation error, which the fixture doesn't produce.
    @Test
    func `Descriptions reveal no witness values`() throws {
        let request = try Fixture.request()
        var dump = ""
        Swift.dump(request, to: &dump)
        Swift.dump(request.witness, to: &dump)
        Swift.dump(request.witness.inputs, to: &dump)
        Swift.dump(request.witness.outputs, to: &dump)

        let text = [String(describing: request), String(reflecting: request), String(describing: request.witness),
                    String(reflecting: request.witness.inputs[0].utxo), dump].joined(separator: "\n")

        #expect(["161", "177", "193", "209", "a1", "b1", "c1", "d1"].allSatisfy { !text.contains($0) })
    }
}

/// Verifies that lookups agree with their witness inputs, as zolana's indexed route requires.
struct TransferProofRequestLookupTests {
    private typealias Fixture = ProofFixtures

    /// Creates a request whose one input has the given witness and lookup.
    /// - Parameters:
    ///   - isDummy: Whether the witness input pads its slot.
    ///   - compact: Whether a padding input is compact, with a zero nullifier.
    ///   - cached: Whether the input comes from the read cache.
    ///   - commitment: Whether the lookup has a commitment.
    ///   - nullifier: Whether the lookup has a nullifier.
    /// - Returns: The request.
    /// - Throws: A ``TransferProofRequest/ValidationError`` if the parts disagree.
    private static func request(isDummy: Bool, compact: Bool, cached: Bool, commitment: Bool, nullifier: Bool) throws
        -> TransferProofRequest {
        let witness = try Fixture.witness(
            isDummy: isDummy, nullifier: compact ? Fixture.field(0) : Fixture.field(0x21),
            cacheTreeID: cached ? Fixture.field(2) : Fixture.field(0), cacheReadHashes: cached ? [Fixture.field(4)] : [],
            cacheIsCached: cached ? [true] : [], cacheReadIndexes: cached ? [0] : []
        )
        let input = try TransferProofRequest.Input(treeSlot: 0, commitment: commitment ? Fixture.field(9) : nil,
                                                   nullifier: nullifier ? Fixture.field(8) : nil)
        return try TransferProofRequest(trees: [try .init(address: Fixture.tree, id: 0)], inputs: [input],
                                        publicInputs: Array(repeating: Fixture.field(1), count: 17),
                                        minContextSlot: nil, witness: witness)
    }

    /// Verifies lookups that agree with their inputs are accepted: a real input's commitment, a cached input
    /// without one, padding without values, and compact padding's nullifier.
    ///
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - compact: Whether padding is compact.
    ///   - cached: Whether the input is cached.
    ///   - commitment: Whether the lookup has a commitment.
    ///   - nullifier: Whether the lookup has a nullifier.
    @Test(arguments: [
        (false, false, false, true, false), (false, false, true, false, false),
        (true, false, false, false, false), (true, true, false, false, true),
    ])
    func `Lookups that agree with their inputs are accepted`(
        isDummy: Bool, compact: Bool, cached: Bool, commitment: Bool, nullifier: Bool
    ) {
        #expect(throws: Never.self) {
            try Self.request(isDummy: isDummy, compact: compact, cached: cached, commitment: commitment,
                             nullifier: nullifier)
        }
    }

    /// Verifies lookups that disagree with their inputs are refused.
    ///
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - compact: Whether padding is compact.
    ///   - cached: Whether the input is cached.
    ///   - commitment: Whether the lookup has a commitment.
    ///   - nullifier: Whether the lookup has a nullifier.
    @Test(arguments: [
        (false, false, false, false, false), (false, false, false, true, true), (false, false, true, true, false),
        (true, false, false, true, false), (true, false, false, false, true), (true, true, false, false, false),
    ])
    func `Lookups that disagree with their inputs are refused`(
        isDummy: Bool, compact: Bool, cached: Bool, commitment: Bool, nullifier: Bool
    ) {
        #expect(throws: TransferProofRequest.ValidationError.invalidLookup) {
            try Self.request(isDummy: isDummy, compact: compact, cached: cached, commitment: commitment,
                             nullifier: nullifier)
        }
    }
}
