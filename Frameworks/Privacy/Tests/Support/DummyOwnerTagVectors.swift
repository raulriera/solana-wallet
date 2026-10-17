import Testing

/// zolana's padding owner tag vectors.
///
/// `DummyOwnerTagVectors.json` copies `test-vectors/dummy_owner_tags.json` unchanged from zolana's
/// main branch at commit f163d0f (Apache-2.0), which adds the rule after v0.4.0-alpha.
/// `DummyOwnerTagVectors-LICENSE.txt` records the source and its digest. Keys are Ed25519 keys whose
/// 32 secret bytes all equal a seed; the resolved tag is a hexadecimal Ed25519 public key.
struct DummyOwnerTagVectors: Decodable, Sendable {
    /// The seed of the sender, who owns the one input.
    let senderSeed: UInt8
    /// The seed of the transfer's recipient.
    let recipientSeed: UInt8
    /// The input's lamports.
    let inputAmount: UInt64
    /// The cases.
    let cases: [Case]

    /// A transfer and the owner tag of its padding outputs.
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The seed of the fee payer.
        let payerSeed: UInt8
        /// The lamports sent to the recipient.
        let sendAmount: UInt64
        /// The padding's encoding: `account` for a reference to the payer, or `inline`.
        let ownerTagKind: String
        /// The view tag that the padding borrows.
        let resolved: String

        /// The vector's name, in test results.
        var testDescription: String { name }

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case name
            case payerSeed = "payer_seed"
            case sendAmount = "send_amount"
            case ownerTagKind = "owner_tag_kind"
            case resolved
        }
    }

    /// The cases where the sender pays the fee.
    var selfPaidCases: [Case] { cases.filter { $0.payerSeed == senderSeed } }

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case senderSeed = "sender_seed"
        case recipientSeed = "recipient_seed"
        case inputAmount = "input_amount"
        case cases
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The owner tag vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "DummyOwnerTagVectors")
    }
}
