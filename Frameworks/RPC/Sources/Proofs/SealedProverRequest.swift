import CryptoKit
import Encoding
import Foundation

/// A Solana Rings prover request encrypted to the prover's attested HPKE key, and the key that opens its answer.
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
    private static let ciphertextField = "Zolana-Tee-Ciphertext"

    /// The encrypted request, ready to send.
    let request: URLRequest

    private let responseKey: SymmetricKey

    /// Encrypts a request's body to the prover's key, bound to its method, route, and query, as a `GET` header or an
    /// octet-stream body.
    ///
    /// - Parameters:
    ///   - request: The unencrypted request to a URL below the endpoint.
    ///   - endpoint: The prover's base URL.
    ///   - key: The prover's attested HPKE key.
    /// - Throws: ``RPCError/encoding`` for a `HEAD` request, a URL outside the endpoint, or a failed encryption.
    init(sealing request: URLRequest, below endpoint: URL, to key: Curve25519.KeyAgreement.PublicKey) throws {
        let method = request.httpMethod ?? "GET"
        guard method != "HEAD", let url = request.url else { throw RPCError.encoding }
        let authenticatedData = try Self.authenticatedData(method: method, url: url, below: endpoint)
        let encapsulatedKey: Data
        let ciphertext: Data
        do {
            var sender = try HPKE.Sender(recipientKey: key, ciphersuite: Self.ciphersuite, info: Self.info)
            ciphertext = try sender.seal(request.httpBody ?? Data(), authenticating: authenticatedData)
            encapsulatedKey = sender.encapsulatedKey
            responseKey = try sender.exportSecret(context: Self.responseContext, outputByteCount: 32)
        } catch {
            throw RPCError.encoding
        }
        var sealed = request
        sealed.setValue(Self.version, forHTTPHeaderField: Self.versionField)
        sealed.setValue(Hex.encode(Array(encapsulatedKey)), forHTTPHeaderField: Self.encapsulatedKeyField)
        if method == "GET" {
            sealed.httpBody = nil
            sealed.setValue(Hex.encode(Array(ciphertext)), forHTTPHeaderField: Self.ciphertextField)
        } else {
            sealed.httpBody = ciphertext
            sealed.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        self.request = sealed
    }

    /// Decrypts the prover's answer to this request.
    ///
    /// - Parameters:
    ///   - body: The response body.
    ///   - response: The prover's HTTP response.
    /// - Returns: The prover's status and body.
    /// - Throws: ``RPCError/InvalidResponse/unauthenticatedAnswer`` for an encrypted answer that doesn't open under
    ///   this request's key or a successful answer without encryption, ``RPCError/InvalidResponse/staleProverKey``
    ///   when the prover can't decrypt the request, or ``RPCError/http(statusCode:retryAfter:)`` for another
    ///   unencrypted answer.
    func open(_ body: Data, response: HTTPURLResponse) throws -> Answer {
        if response.value(forHTTPHeaderField: Self.versionField) == Self.version {
            return try Self.open(body, using: responseKey)
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

    /// Returns the authenticated data that binds a request to its method, its route below the endpoint, and its
    /// query without API keys.
    ///
    /// - Parameters:
    ///   - method: The HTTP method, such as `POST`.
    ///   - url: The request's URL.
    ///   - endpoint: The prover's base URL.
    /// - Returns: The method, the URL's percent-encoded path without the endpoint's path, or `/` when none remains,
    ///   and the query's non-empty pairs other than `api-key` pairs, in order.
    /// - Throws: ``RPCError/encoding`` for a URL whose scheme, host, or port differs from the endpoint's, or whose
    ///   path isn't below the endpoint's path.
    static func authenticatedData(method: String, url: URL, below endpoint: URL) throws -> [UInt8] {
        let endpointPath = endpoint.path(percentEncoded: true)
        let basePath = endpointPath.hasSuffix("/") ? String(endpointPath.dropLast()) : endpointPath
        let path = url.path(percentEncoded: true)
        guard url.scheme == endpoint.scheme, url.host() == endpoint.host(), url.port == endpoint.port,
            path.hasPrefix(basePath)
        else { throw RPCError.encoding }
        let route = path.dropFirst(basePath.count)
        guard route.isEmpty || route.hasPrefix("/") else { throw RPCError.encoding }
        let pairs = (url.query(percentEncoded: true) ?? "").split(separator: "&").filter { !isAPIKey($0) }
        let query = pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&")
        return Array("\(method) \(route.isEmpty ? "/" : route)\(query)".utf8)
    }

    /// Returns whether a query pair's percent-decoded key is `api-key`.
    ///
    /// - Parameter pair: The query pair, with or without a value.
    /// - Returns: `true` for an `api-key` pair; `false` for another key or one with an invalid percent escape.
    private static func isAPIKey(_ pair: Substring) -> Bool {
        pair.prefix { $0 != "=" }.removingPercentEncoding == "api-key"
    }
}
