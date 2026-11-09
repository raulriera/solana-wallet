import CryptoKit
import Testing
@testable import Attestation
@testable import RPC

struct NitroPolicyProverTests {
    @Test(arguments: [(NitroPolicy.devnet, "DevnetNitroPolicy"), (.mainnet, "MainnetNitroPolicy")])
    func `Pinned policies match their deployment files`(policy: NitroPolicy, file: String) throws {
        let deployment = try NitroPolicyFixture.deployment(named: file)
        let pinned = try deployment.policy(root: NitroCertificateChain.awsNitroEnclavesRoot)

        #expect(deployment.platform == "aws-nitro")
        #expect(deployment.gpu == "optional")
        #expect(policy.measurements == pinned.measurements)
        #expect(policy.publicKey == nil)
        #expect(policy.root == pinned.root)
        #expect(policy.maximumAge == pinned.maximumAge)
    }

    @Test(arguments: [
        (NitroPolicy.devnet, "RecordedDevnetNitroAttestation"),
        (.mainnet, "RecordedMainnetNitroAttestation"),
    ])
    func `A recorded attestation yields its HPKE key under its network's policy`(
        policy: NitroPolicy,
        file: String
    ) throws {
        let recorded = try RecordedNitroAttestation.load(named: file)

        let key = try Self.publicKey(of: recorded, under: policy)

        #expect(Array(key.rawRepresentation) == (try recorded.hpkePublicKey))
    }

    @Test(arguments: [
        (NitroPolicy.mainnet, "RecordedDevnetNitroAttestation"),
        (.devnet, "RecordedMainnetNitroAttestation"),
    ])
    func `A recorded attestation fails the other network's policy`(policy: NitroPolicy, file: String) throws {
        let recorded = try RecordedNitroAttestation.load(named: file)

        #expect(throws: NitroPolicy.ValidationError.unexpectedMeasurement) {
            try Self.publicKey(of: recorded, under: policy)
        }
    }

    private static func publicKey(
        of recorded: RecordedNitroAttestation,
        under policy: NitroPolicy
    ) throws -> Curve25519.KeyAgreement.PublicKey {
        let nonce = try fixtureBytes(recorded.nonce)
        let reportData = try ProverAttestation.reportData(nonce: nonce, key: recorded.hpkePublicKey)
        return try recorded.publicKey(under: policy, userData: reportData)
    }
}
