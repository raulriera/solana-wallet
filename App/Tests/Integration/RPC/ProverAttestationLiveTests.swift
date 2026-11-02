import CryptoKit
import Foundation
import Testing
@testable import Attestation
@testable import RPC

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ProverAttestationLiveTests {
    @Test(arguments: [(Network.mainnet, NitroPolicy.mainnet), (.devnet, .devnet)])
    func `The network's prover attests its pinned key now`(network: Network, policy: NitroPolicy) async throws {
        let key = try await Zolana(network: network).attestedKey.key()

        #expect(Array(key.rawRepresentation) == policy.publicKey)
    }
}
