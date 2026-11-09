import CryptoKit
import Foundation
import Testing
@testable import RPC

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ProverAttestationLiveTests {
    @Test(arguments: [Network.mainnet, .devnet])
    func `The network's prover passes its policy now`(network: Network) async throws {
        let key = try await Zolana(network: network).attestedKey.key()

        #expect(key.rawRepresentation.count == 32)
    }
}
