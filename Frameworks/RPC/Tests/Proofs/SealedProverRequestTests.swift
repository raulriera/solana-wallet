import CryptoKit
import Encoding
import Foundation
import Testing
@testable import RPC

struct SealedProverRequestTests {
    private static let body = Data(#"{"inputs":["secret"]}"#.utf8)

    @Test(arguments: try EncryptedProverVectors.load().authenticatedDataCases)
    func `The test prover authenticates each vector target as zolana does`(
        vector: EncryptedProverVectors.AuthenticatedDataCase
    ) {
        let authenticatedData = TestProver.authenticatedData(method: vector.method, target: vector.requestTarget)

        #expect(authenticatedData == Array(vector.aad.utf8))
    }

    @Test(arguments: [
        ("GET", "https://prover.example", "https://prover.example/tee/v1/attestation?nonce=ab",
         "GET /tee/v1/attestation?nonce=ab"),
        ("POST", "https://prover.example/", "https://prover.example/prove/transfer_2_2/indexed",
         "POST /prove/transfer_2_2/indexed"),
        ("GET", "https://prover.example", "https://prover.example/prove/x/status?jobId=a1&&api-key=k",
         "GET /prove/x/status?jobId=a1"),
        ("GET", "https://gateway.example/v1/zolana?api-key=fixture-key",
         "https://gateway.example/v1/zolana/tee/v1/attestation?api-key=fixture-key&nonce=ab",
         "GET /tee/v1/attestation?nonce=ab"),
        ("POST", "https://gateway.example/v1/zolana?api-key=fixture-key",
         "https://gateway.example/v1/zolana/prove/transfer_2_2/indexed?api-key=fixture-key",
         "POST /prove/transfer_2_2/indexed"),
        ("GET", "https://gateway.example/v1/zolana?api-key=fixture-key",
         "https://gateway.example/v1/zolana?api-key=fixture-key", "GET /"),
    ] as [(String, String, String, String)])
    func `A request authenticates its method, its route below the endpoint and its query without API keys`(
        method: String,
        endpoint: String,
        url: String,
        expected: String
    ) throws {
        let authenticatedData = try SealedProverRequest.authenticatedData(
            method: method,
            url: Self.url(url),
            below: Self.url(endpoint)
        )

        #expect(authenticatedData == Array(expected.utf8))
    }

    @Test
    func `A sealed POST request carries its ciphertext as an octet-stream body`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        var request = try Self.request("POST", "https://prover.example/prove/transfer_2_2", body: Self.body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fixture-key", forHTTPHeaderField: "X-API-Key")

        let sealed = try SealedProverRequest(
            sealing: request,
            below: Self.url("https://prover.example"),
            to: prover.publicKey
        ).request

        #expect(sealed.url == request.url)
        #expect(sealed.httpMethod == "POST")
        #expect(sealed.httpBody?.count == Self.body.count + 16)
        #expect(sealed.httpBody != Self.body)
        #expect(sealed.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(sealed.value(forHTTPHeaderField: "X-API-Key") == "fixture-key")
        #expect(sealed.value(forHTTPHeaderField: "Zolana-Tee") == "v1")
        #expect(Hex.decode(sealed.value(forHTTPHeaderField: "Zolana-Tee-Enc") ?? "")?.count == 32)
        #expect(sealed.value(forHTTPHeaderField: "Zolana-Tee-Ciphertext") == nil)
    }

    @Test
    func `A sealed GET request carries its ciphertext in a header and has no body`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let request = try Self.request("GET", "https://prover.example/prove/transfer_2_2/status?jobId=a1")

        let sealed = try SealedProverRequest(
            sealing: request,
            below: Self.url("https://prover.example"),
            to: prover.publicKey
        ).request

        #expect(sealed.url == request.url)
        #expect(sealed.httpBody == nil)
        #expect(sealed.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(sealed.value(forHTTPHeaderField: "Zolana-Tee") == "v1")
        #expect(Hex.decode(sealed.value(forHTTPHeaderField: "Zolana-Tee-Enc") ?? "")?.count == 32)
        #expect(Hex.decode(sealed.value(forHTTPHeaderField: "Zolana-Tee-Ciphertext") ?? "")?.count == 16)
    }

    @Test(arguments: [
        ("HEAD", "https://gateway.example/v1/zolana/prove/x?api-key=fixture-key"),
        ("POST", "http://gateway.example/v1/zolana/prove/x"),
        ("POST", "https://other.example/v1/zolana/prove/x"),
        ("POST", "https://gateway.example:8443/v1/zolana/prove/x"),
        ("POST", "https://gateway.example/v1/zolanax/prove/x"),
        ("POST", "https://gateway.example/prove/x"),
    ])
    func `A HEAD request or a URL outside the endpoint can't be sealed`(method: String, url: String) throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let request = try Self.request(method, url)
        let endpoint = try Self.url("https://gateway.example/v1/zolana?api-key=fixture-key")

        #expect(throws: RPCError.encoding) {
            try SealedProverRequest(sealing: request, below: endpoint, to: prover.publicKey)
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

    @Test(arguments: [
        ("POST", "https://prover.example", "https://prover.example/prove/transfer_2_2", #"{"inputs":["secret"]}"#),
        ("GET", "https://prover.example", "https://prover.example/prove/transfer_2_2/status?jobId=a1", ""),
        ("POST", "https://gateway.example/v1/zolana?api-key=fixture-key",
         "https://gateway.example/v1/zolana/prove/transfer_2_2?api-key=fixture-key", #"{"inputs":["secret"]}"#),
        ("GET", "https://gateway.example/v1/zolana?api-key=fixture-key",
         "https://gateway.example/v1/zolana/tee/v1/attestation?api-key=fixture-key&nonce=ab", ""),
    ])
    func `A sealed request opens at the prover and the prover's answer opens with the request`(
        method: String,
        endpoint: String,
        url: String,
        body: String
    ) throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let answerBody = Data(#"{"proof":"ok"}"#.utf8)
        let sealed = try SealedProverRequest(
            sealing: Self.request(method, url, body: Data(body.utf8)),
            below: Self.url(endpoint),
            to: prover.publicKey
        )

        let opened = try prover.open(sealed.request)
        let (answer, response) = try opened.answer(status: 200, body: answerBody)
        let decrypted = try sealed.open(answer, response: response)

        #expect(opened.body == Data(body.utf8))
        #expect(decrypted == .init(status: 200, body: answerBody))
    }

    @Test
    func `An encrypted 503 answer opens into its status and body`() throws {
        let prover = try TestProver(vectors: EncryptedProverVectors.load())
        let sealed = try Self.sealed(to: prover)
        let answerBody = Data(#"{"code":"busy"}"#.utf8)
        let (answer, response) = try prover.open(sealed.request).answer(status: 503, body: answerBody)

        let decrypted = try sealed.open(answer, response: response)

        #expect(decrypted == .init(status: 503, body: answerBody))
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

        let (answer, response) = try prover.open(second.request).answer(status: 200, body: Data())

        #expect(
            first.request.value(forHTTPHeaderField: "Zolana-Tee-Enc")
                != second.request.value(forHTTPHeaderField: "Zolana-Tee-Enc")
        )
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

    private static func sealed(to prover: TestProver) throws -> SealedProverRequest {
        try SealedProverRequest(
            sealing: request("POST", "https://prover.example/prove/transfer_2_2", body: body),
            below: url("https://prover.example"),
            to: prover.publicKey
        )
    }
}
