import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PendingLabelTests {
    @Test(arguments: [false, true])
    func `The label shows in a form row while pending or not`(isPending: Bool) async throws {
        let hosted = try HostedWindow(Form {
            Button {} label: {
                PendingLabel(title: "Send", isPending: isPending)
            }
        })
        defer { hosted.close() }

        #expect(try await hosted.appears())
    }
}
