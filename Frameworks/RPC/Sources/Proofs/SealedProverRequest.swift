import CryptoKit
import Encoding
import Foundation

/// A Solana Rings prover request body encrypted to the prover's attested HPKE key, and the key that opens its
/// answer.
struct SealedProverRequest: Sendable {
    /// A prover's decrypted answer.
    struct Answer: Sendable, Equatable {
        /// The HTTP status that the prover gave the request.
        let status: Int
        let body: Data
    }

    /// The JSON body of a prover's unencrypted refusal.
    private struct Refusal: Decodable {
        let code: String
    }

    private static let ciphersuite = HPKE.Ciphersuite(
        kem: .Curve25519_HKDF_SHA256,
        kdf: .HKDF_SHA256,
        aead: .AES_GCM_256
    )
    private static let info = Data("zolana/prover-tee/v1".utf8)
    private static let responseContext = Data("zolana/prover-tee/v1/response".utf8)
    private static let versionField = "Zolana-Tee"
    private static let version = "v1"
    private static let encapsulatedKeyField = "Zolana-Tee-Enc"

    /// The encrypted JSON body.
    let body: Data

    /// The header fields that mark the body as encrypted and carry its encapsulated key.
    let headers: [String: String]

    private let responseKey: SymmetricKey

    /// Encrypts a JSON body to the prover's key, bound to a `POST` to a route on the prover's host.
    ///
    /// - Parameters:
    ///   - body: The value to encrypt as the JSON request body.
    ///   - route: One or more path components without a leading slash.
    ///   - key: The prover's attested HPKE key.
    /// - Throws: ``RPCError/encoding`` for a body that can't be encoded or encrypted.
    init(sealing body: some Encodable, at route: String, to key: Curve25519.KeyAgreement.PublicKey) throws {
        guard let plaintext = try? JSONEncoder().encode(body) else { throw RPCError.encoding }
        do {
            var sender = try HPKE.Sender(recipientKey: key, ciphersuite: Self.ciphersuite, info: Self.info)
            self.body = try sender.seal(plaintext, authenticating: Array("POST /\(route)".utf8))
            responseKey = try sender.exportSecret(context: Self.responseContext, outputByteCount: 32)
            headers = [
                Self.versionField: Self.version,
                Self.encapsulatedKeyField: Hex.encode(Array(sender.encapsulatedKey)),
                "Content-Type": "application/octet-stream",
            ]
        } catch {
            throw RPCError.encoding
        }
    }

    /// Decrypts the prover's answer to this request and returns the body of a successful answer.
    ///
    /// - Parameters:
    ///   - body: The response body.
    ///   - response: The prover's HTTP response.
    /// - Returns: The decrypted body.
    /// - Throws: ``RPCError/InvalidResponse/unauthenticatedAnswer`` for an encrypted answer that doesn't open under
    ///   this request's key or a successful answer without encryption, ``RPCError/InvalidResponse/staleProverKey``
    ///   when the prover can't decrypt the request, or ``RPCError/http(statusCode:retryAfter:)`` for an unsuccessful
    ///   decrypted status or another unencrypted answer.
    func open(_ body: Data, response: HTTPURLResponse) throws -> Data {
        if response.value(forHTTPHeaderField: Self.versionField) == Self.version {
            let answer = try Self.open(body, using: responseKey)
            guard (200..<300).contains(answer.status) else {
                throw RPCError.http(statusCode: answer.status, retryAfter: nil)
            }
            return answer.body
        }
        if response.statusCode == 400,
            (try? JSONDecoder().decode(Refusal.self, from: body))?.code == "tee_decryption_failed" {
            throw RPCError.invalidResponse(.staleProverKey)
        }
        throw RPCError(response: response) ?? RPCError.invalidResponse(.unauthenticatedAnswer)
    }

    /// Decrypts a prover's encrypted answer under a response key.
    ///
    /// - Parameters:
    ///   - answer: The answer's nonce, ciphertext, and tag.
    ///   - responseKey: The request's exported response key.
    /// - Returns: The prover's status and body.
    /// - Throws: ``RPCError/InvalidResponse/unauthenticatedAnswer`` for an answer that doesn't open under the key or
    ///   holds no status.
    static func open(_ answer: some DataProtocol, using responseKey: SymmetricKey) throws -> Answer {
        guard let box = try? AES.GCM.SealedBox(combined: answer),
            let plaintext = try? AES.GCM.open(box, using: responseKey), plaintext.count >= 2
        else { throw RPCError.invalidResponse(.unauthenticatedAnswer) }
        let start = plaintext.startIndex
        return Answer(
            status: Int(plaintext[start]) << 8 | Int(plaintext[start + 1]),
            body: plaintext.subdata(in: (start + 2)..<plaintext.endIndex)
        )
    }
}
