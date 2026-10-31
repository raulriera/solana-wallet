import Testing

struct RecordedNitroAttestation: Decodable, Sendable {
    let capturedAt: Int
    let attestation: Attestation

    private enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case attestation
    }

    struct Attestation: Decodable, Sendable {
        let evidence: Evidence
    }

    struct Evidence: Decodable, Sendable {
        let document: String
    }

    static func load() throws -> Self {
        try fixture(named: "RecordedNitroAttestation")
    }
}
