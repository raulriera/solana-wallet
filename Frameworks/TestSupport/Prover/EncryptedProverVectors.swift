import Testing

struct EncryptedProverVectors: Decodable, Sendable {
    struct AuthenticatedDataCase: Decodable, Sendable, CustomTestStringConvertible {
        let method: String
        let requestTarget: String
        let aad: String

        var testDescription: String { "\(method) \(requestTarget)" }

        private enum CodingKeys: String, CodingKey {
            case method
            case requestTarget = "request_target"
            case aad
        }
    }

    let ikm: String
    let hpkePublicKey: String
    let nonce: String
    let reportDataWithoutGPU: String
    let method: String
    let requestURI: String
    let encapsulatedKey: String
    let ciphertext: String
    let plaintext: String
    let responseKey: String
    let responseStatus: Int
    let responseBody: String
    let encryptedResponse: String
    let authenticatedDataCases: [AuthenticatedDataCase]

    private enum CodingKeys: String, CodingKey {
        case ikm
        case hpkePublicKey = "hpke_public_key"
        case nonce
        case reportDataWithoutGPU = "report_data_no_gpu"
        case method
        case requestURI = "request_uri"
        case encapsulatedKey = "enc"
        case ciphertext
        case plaintext
        case responseKey = "response_key"
        case responseStatus = "response_status"
        case responseBody = "response_body"
        case encryptedResponse = "encrypted_response"
        case authenticatedDataCases = "aad_cases"
    }

    static func load() throws -> Self {
        try fixture(named: "EncryptedProverVectors")
    }
}
