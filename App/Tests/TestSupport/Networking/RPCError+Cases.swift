import RPC

extension RPCError {
    var statusCode: Int? {
        if case .http(let statusCode, _) = self { statusCode } else { nil }
    }

    var serverCode: Int? {
        if case .server(let code, _) = self { code } else { nil }
    }

    var preflightSimulation: SimulateTransaction.Value? {
        if case .preflight(_, let simulation) = self { simulation } else { nil }
    }
}
