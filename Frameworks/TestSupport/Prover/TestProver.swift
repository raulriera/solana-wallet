import CryptoKit
import Encoding
import Foundation
import Testing

struct TestProver: Sendable {
    struct Request: Sendable {
        let url: URL
        let body: Data
        let responseKey: SymmetricKey

        func answer(status: Int, body: Data) throws -> (Data, HTTPURLResponse) {
            let plaintext = Data([UInt8(status >> 8), UInt8(status & 0xff)]) + body
            let answer = try #require(try AES.GCM.seal(plaintext, using: responseKey).combined)
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Spr-Tee": "v1"])
            )
            return (answer, response)
        }
    }

    private static let ciphersuite = HPKE.Ciphersuite(
        kem: .Curve25519_HKDF_SHA256,
        kdf: .HKDF_SHA256,
        aead: .AES_GCM_256
    )
    private static let info = Data("zolana/prover-tee/v1".utf8)
    private static let responseContext = Data("zolana/prover-tee/v1/response".utf8)
    private static let suiteID = Array("KEM".utf8) + [0x00, 0x20]

    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    var publicKey: Curve25519.KeyAgreement.PublicKey { privateKey.publicKey }

    init(vectors: EncryptedProverVectors) throws {
        let extracted = HKDF<SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: Self.labeled("dkp_prk", try fixtureBytes(vectors.ikm))),
            salt: [UInt8]()
        )
        let secret = HKDF<SHA256>.expand(
            pseudoRandomKey: extracted,
            info: [0x00, 0x20] + Self.labeled("sk", []),
            outputByteCount: 32
        )
        privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
        try #require(Array(privateKey.publicKey.rawRepresentation) == (try fixtureBytes(vectors.hpkePublicKey)))
    }

    static func authenticatedData(method: String, target: String) -> [UInt8] {
        Array("\(method) \(target)".utf8)
    }

    func open(_ request: URLRequest) throws -> Request {
        let url = try #require(request.url)
        let method = try #require(request.httpMethod)
        try #require(request.value(forHTTPHeaderField: "Spr-Tee") == "v1")
        let encapsulatedKey = try Self.headerBytes("Spr-Tee-Enc", of: request)
        let ciphertext = try #require(request.httpBody)
        let path = url.path(percentEncoded: true)
        let target = (path.isEmpty ? "/" : path) + (url.query(percentEncoded: true).map { "?" + $0 } ?? "")
        var recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: Self.ciphersuite,
            info: Self.info,
            encapsulatedKey: Data(encapsulatedKey)
        )
        let authenticatedData = Self.authenticatedData(method: method, target: target)
        let body = try recipient.open(ciphertext, authenticating: authenticatedData)
        return Request(
            url: url,
            body: body,
            responseKey: try recipient.exportSecret(context: Self.responseContext, outputByteCount: 32)
        )
    }

    private static func headerBytes(_ field: String, of request: URLRequest) throws -> [UInt8] {
        let value = try #require(request.value(forHTTPHeaderField: field))
        return try #require(Hex.decode(value))
    }

    private static func labeled(_ label: String, _ value: [UInt8]) -> [UInt8] {
        Array("HPKE-v1".utf8) + suiteID + Array(label.utf8) + value
    }
}
