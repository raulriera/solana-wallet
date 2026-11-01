import CryptoKit
import Encoding
import Foundation
import Testing
@testable import RPC

struct StubProver: Sendable {
    typealias Answer = @Sendable (_ body: Data) throws -> (status: Int, body: String)

    private static let claimedKey: AttestedProverKey.Verification = { attestation, _, _, _ in
        try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Hex.decode(attestation.hpkePublicKey) ?? [])
    }

    private let prover: TestProver
    private let answer: Answer

    init(answer: @escaping Answer) throws {
        prover = try TestProver(vectors: .load())
        self.answer = answer
    }

    static func zolana(on network: Network = .devnet, transport: any HTTPTransport) -> Zolana {
        Zolana(network: network, transport: transport, verify: claimedKey)
    }

    static func attestation(of key: Curve25519.KeyAgreement.PublicKey) -> String {
        let hex = Hex.encode(Array(key.rawRepresentation))
        return #"{"platform":"aws-nitro","hpke_public_key":"\#(hex)","gpu":null,"evidence":{"document":"00"}}"#
    }

    func respond(to request: URLRequest) throws -> (Data, URLResponse)? {
        if request.value(forHTTPHeaderField: "Zolana-Tee") != nil {
            let sealed = try prover.open(request)
            let (status, body) = try answer(sealed.body)
            return try sealed.answer(status: status, body: Data(body.utf8))
        }
        guard request.httpMethod == "GET", request.url?.path().hasSuffix("/tee/v1/attestation") == true else {
            return nil
        }
        return try httpReply(to: request, body: Self.attestation(of: prover.publicKey))
    }
}
