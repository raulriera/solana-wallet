import Foundation

/// The JSON-RPC envelope surrounding a typed request's parameters.
struct JSONRPCRequest<Request: RPCRequest>: Encodable {
    let jsonrpc = "2.0"
    let method = Request.method
    let id: String
    let params: Request
}

/// A validated JSON-RPC envelope containing a result or a server error.
struct JSONRPCResponse<Value: Decodable>: Decodable {
    /// The response identifier, or `nil` for an unattributed error.
    let id: String?
    let result: Result<Value, ServerError>

    /// The error payload supplied by a JSON-RPC server.
    struct ServerError: Decodable, Error {
        let code: Int
        let message: String
        let simulation: SimulateTransaction.Value?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(Int.self, forKey: .code)
            message = try container.decode(String.self, forKey: .message)
            simulation = code == -32002
                ? try? container.decode(SimulateTransaction.Value.self, forKey: .data)
                : nil
        }

        /// The field names in a JSON-RPC server error.
        private enum CodingKeys: String, CodingKey {
            case code, message, data
        }
    }

    /// The field names in a JSON-RPC response envelope.
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .jsonrpc) == "2.0" else {
            throw RPCError.invalidResponse(.unsupportedVersion)
        }
        id = try container.decode(String?.self, forKey: .id)
        guard container.contains(.result) != container.contains(.error) else {
            throw RPCError.invalidResponse(.invalidEnvelope)
        }
        if container.contains(.error) {
            result = .failure(try container.decode(ServerError.self, forKey: .error))
        } else {
            result = .success(try container.decode(Value.self, forKey: .result))
        }
    }
}
