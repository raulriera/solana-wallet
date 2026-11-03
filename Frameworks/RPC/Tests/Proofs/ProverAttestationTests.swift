import Attestation
import Foundation
import Testing
@testable import RPC

struct ProverAttestationTests {
    @Test(arguments: [
        ("platform", #""dstack-tdx""#, NitroPolicy.devnet),
        ("gpu", nil, .devnet),
        ("gpu", #""nras-verdict""#, .devnet),
        ("hpke_public_key", #""CF2254CFF568F3401272B0B5FC965917938498E0AE4A41391B04F6924A93E033""#, .devnet),
        ("evidence", #"{"document":"zz"}"#, .devnet),
        ("evidence", #"{"document":"00"}"#, .devnet),
        (nil, nil, .mainnet),
    ] as [(String?, String?, NitroPolicy)])
    func `An attestation outside the AWS Nitro contract or the policy is untrusted`(
        field: String?,
        value: String?,
        policy: NitroPolicy
    ) throws {
        let recorded = try RecordedNitroAttestation.load(named: "RecordedDevnetNitroAttestation")
        var object = recorded.responseObject
        if let field {
            object[field] = try value.map {
                try JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed)
            }
        }
        let body = try JSONSerialization.data(withJSONObject: object)
        let nonce = try fixtureBytes(recorded.nonce)

        #expect(throws: RPCError.invalidResponse(.untrustedProver)) {
            try JSONDecoder().decode(ProverAttestation.self, from: body)
                .publicKey(for: nonce, under: policy, at: recorded.capturedDate)
        }
    }

    @Test
    func `Report data binds the nonce and the key without a GPU verdict`() throws {
        let vectors = try EncryptedProverVectors.load()

        let reportData = ProverAttestation.reportData(
            nonce: try fixtureBytes(vectors.nonce),
            key: try fixtureBytes(vectors.hpkePublicKey)
        )

        #expect(reportData == (try fixtureBytes(vectors.reportDataWithoutGPU)))
    }
}
