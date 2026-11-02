import CryptoKit
import Encoding
import Foundation
import Testing
@testable import RPC

struct SealedProverRequestTests {
    private struct Reading: Encodable {
        let inputs: [String]
    }

    private static let reading = Reading(inputs: ["secret"])

    private static let body = Data(#"{"inputs":["secret"]}"#.utf8)

    @Test(arguments: try EncryptedProverVectors.load().authenticatedDataCases)
    func `The test prover authenticates each vector target as zolana does`(
        vector: EncryptedProverVectors.AuthenticatedDataCase
    ) {
        let authenticatedData = TestProver.authenticatedData(method: vector.method, target: vector.requestTarget)

        #expect(authenticatedData == Array(vector.aad.utf8))
    }

    @Test
    func `A sealed body is ciphertext with headers that mark it as encrypted with an encapsulated key`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())

        let sealed = try SealedProverRequest(sealing: Self.reading, at: "prove/transfer_2_2", to: prover.publicKey)

        #expect(sealed.body.count == Self.body.count + 16)
        #expect(sealed.body != Self.body)
        #expect(sealed.headers.keys.sorted() == ["Content-Type", "Zolana-Tee", "Zolana-Tee-Enc"])
        #expect(sealed.headers["Content-Type"] == "application/octet-stream")
        #expect(sealed.headers["Zolana-Tee"] == "v1")
        #expect(Hex.decode(sealed.headers["Zolana-Tee-Enc"] ?? "")?.count == 32)
    }

    @Test
    func `A sealed body doesn't open at another route`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let sealed = try SealedProverRequest(sealing: Self.reading, at: "prove/transfer_2_2", to: prover.publicKey)

        #expect(throws: CryptoKitError.self) {
            try prover.open(Self.request(posting: sealed, at: "prove/transfer_2_1"))
        }
    }

    @Test
    func `The vector request opens at the prover and exports the vector response key`() throws {
        let vectors = try EncryptedProverVectors.load()
        let prover = try TestProver(vectors: vectors)
        var request = try Self.request(
            vectors.method,
            "https://prover.example" + vectors.requestURI,
            body: Data(fixtureBytes(vectors.ciphertext))
        )
        request.setValue("v1", forHTTPHeaderField: "Zolana-Tee")
        request.setValue(vectors.encapsulatedKey, forHTTPHeaderField: "Zolana-Tee-Enc")
        let responseKey = SymmetricKey(data: try fixtureBytes(vectors.responseKey))

        let opened = try prover.open(request)

        #expect(opened.body == Data(vectors.plaintext.utf8))
        #expect(opened.responseKey == responseKey)
    }

    @Test
    func `The vector answer opens under the vector response key into its status and body`() throws {
        let vectors = try EncryptedProverVectors.load()

        let answer = try SealedProverRequest.open(
            fixtureBytes(vectors.encryptedResponse),
            using: SymmetricKey(data: fixtureBytes(vectors.responseKey))
        )

        #expect(answer == .init(status: vectors.responseStatus, body: Data(vectors.responseBody.utf8)))
    }

    @Test(arguments: ["prove/transfer_2_2", "prove/transfer_confidential_1_2/indexed"])
    func `A sealed body opens at the prover at its route and the prover's answer opens with the request`(
        route: String
    ) throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let answerBody = Data(#"{"proof":"ok"}"#.utf8)
        let sealed = try SealedProverRequest(sealing: Self.reading, at: route, to: prover.publicKey)

        let opened = try prover.open(Self.request(posting: sealed, at: route))
        let (answer, response) = try opened.answer(status: 200, body: answerBody)
        let decrypted = try sealed.open(answer, response: response)

        #expect(opened.body == Self.body)
        #expect(decrypted == answerBody)
    }

    @Test
    func `An encrypted unsuccessful answer surfaces its status`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let sealed = try Self.sealed(to: prover)
        let (answer, response) = try prover.open(Self.request(posting: sealed)).answer(
            status: 503,
            body: Data(#"{"code":"busy"}"#.utf8)
        )

        #expect(throws: RPCError.http(statusCode: 503, retryAfter: nil)) { try sealed.open(answer, response: response) }
    }

    @Test(arguments: [
        (200, [:], #"{"proof":"ok"}"#, RPCError.invalidResponse(.unauthenticatedAnswer)),
        (400, [:], #"{"code":"tee_decryption_failed"}"#, .invalidResponse(.staleProverKey)),
        (400, [:], #"{"code":"tee_request_malformed"}"#, .http(statusCode: 400, retryAfter: nil)),
        (429, ["Retry-After": "5"], #"{"code":"attestation_busy"}"#, .http(statusCode: 429, retryAfter: "5")),
    ] as [(Int, [String: String], String, RPCError)])
    func `An unencrypted answer is refused by its status and code`(
        status: Int,
        headers: [String: String],
        body: String,
        error: RPCError
    ) throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let sealed = try Self.sealed(to: prover)
        let url = try Self.url("https://prover.example/prove/transfer_2_2")
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
        )

        #expect(throws: error) { try sealed.open(Data(body.utf8), response: response) }
    }

    @Test
    func `An answer shorter than a nonce and a tag is unauthenticated`() throws {
        let vectors = try EncryptedProverVectors.load()
        let answer = Array(try fixtureBytes(vectors.encryptedResponse).prefix(27))
        let responseKey = SymmetricKey(data: try fixtureBytes(vectors.responseKey))

        #expect(throws: RPCError.invalidResponse(.unauthenticatedAnswer)) {
            try SealedProverRequest.open(answer, using: responseKey)
        }
    }

    @Test
    func `An answer with a changed byte is unauthenticated`() throws {
        let vectors = try EncryptedProverVectors.load()
        var answer = try fixtureBytes(vectors.encryptedResponse)
        answer[12] ^= 0x01
        let responseKey = SymmetricKey(data: try fixtureBytes(vectors.responseKey))

        #expect(throws: RPCError.invalidResponse(.unauthenticatedAnswer)) {
            try SealedProverRequest.open(answer, using: responseKey)
        }
    }

    @Test(arguments: [0, 1])
    func `An authenticated answer without a two-byte status is unauthenticated`(count: Int) throws {
        let responseKey = SymmetricKey(data: try fixtureBytes(EncryptedProverVectors.load().responseKey))
        let answer = try #require(try AES.GCM.seal(Data(count: count), using: responseKey).combined)

        #expect(throws: RPCError.invalidResponse(.unauthenticatedAnswer)) {
            try SealedProverRequest.open(answer, using: responseKey)
        }
    }

    @Test
    func `An answer sealed for another request is unauthenticated`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let first = try Self.sealed(to: prover)
        let second = try Self.sealed(to: prover)

        let (answer, response) = try prover.open(Self.request(posting: second)).answer(status: 200, body: Data())

        #expect(first.headers["Zolana-Tee-Enc"] != second.headers["Zolana-Tee-Enc"])
        #expect(throws: RPCError.invalidResponse(.unauthenticatedAnswer)) { try first.open(answer, response: response) }
    }

    private static func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private static func request(_ method: String, _ url: String, body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try Self.url(url))
        request.httpMethod = method
        request.httpBody = body
        return request
    }

    private static func request(posting sealed: SealedProverRequest, at route: String = "prove/transfer_2_2") throws
        -> URLRequest {
        var request = try Self.request("POST", "https://prover.example/" + route, body: sealed.body)
        for (field, value) in sealed.headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }

    private static func sealed(to prover: TestProver) throws -> SealedProverRequest {
        try SealedProverRequest(sealing: reading, at: "prove/transfer_2_2", to: prover.publicKey)
    }
}
