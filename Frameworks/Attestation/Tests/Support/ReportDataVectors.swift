struct ReportDataVectors: Decodable, Sendable {
    let hpkePublicKey: String
    let nonce: String
    let reportDataWithoutGPU: String

    private enum CodingKeys: String, CodingKey {
        case hpkePublicKey = "hpke_public_key"
        case nonce
        case reportDataWithoutGPU = "report_data_no_gpu"
    }

    static func load() throws -> Self {
        try fixture(named: "EncryptedProverVectors")
    }
}
