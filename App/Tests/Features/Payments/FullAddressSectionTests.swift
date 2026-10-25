import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Shows the shared address section in a real window.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FullAddressSectionTests {
    /// The section shows inside a form, as the recipient and account screens use it.
    /// - Throws: A test prerequisite error.
    @Test
    func `The section shows in a form`() async throws {
        let address = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        let hosted = try HostedWindow(Form { FullAddressSection(address: address) })
        defer { hosted.close() }

        #expect(try await hosted.appears())
    }
}
