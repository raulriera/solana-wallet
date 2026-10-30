import Testing

struct DummyOwnerTagVectors: Decodable, Sendable {
    let senderSeed: UInt8
    let recipientSeed: UInt8
    let inputAmount: UInt64
    let cases: [Case]

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let payerSeed: UInt8
        let sendAmount: UInt64
        let ownerTagKind: String
        let resolved: String

        var testDescription: String { name }

        private enum CodingKeys: String, CodingKey {
            case name
            case payerSeed = "payer_seed"
            case sendAmount = "send_amount"
            case ownerTagKind = "owner_tag_kind"
            case resolved
        }
    }

    var selfPaidCases: [Case] { cases.filter { $0.payerSeed == senderSeed } }

    private enum CodingKeys: String, CodingKey {
        case senderSeed = "sender_seed"
        case recipientSeed = "recipient_seed"
        case inputAmount = "input_amount"
        case cases
    }

    static func load() throws -> Self {
        try fixture(named: "DummyOwnerTagVectors")
    }
}
