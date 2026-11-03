import CryptoKit
import Testing
@testable import Attestation

struct NitroCertificateChainRootTests {
    @Test
    func `The AWS Nitro Enclaves root has its published fingerprint`() throws {
        let fingerprint = try fixtureBytes("641a0321a3e244efe456463195d606317ed7cdcc3c1756e09893f3c68f79bb5b")

        #expect(Array(SHA256.hash(data: NitroCertificateChain.awsNitroEnclavesRoot)) == fingerprint)
    }
}
