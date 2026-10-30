import SwiftUI
import Testing
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AdaptiveArrangementTests {
    @MainActor final class Frames {
        var primary: CGRect?
        var secondary: CGRect?
        var accessory: CGRect?
    }

    private func arrange(in size: CGSize) async throws -> Frames {
        let frames = Frames()
        let hosted = try HostedWindow(
            ArrangementView {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("arrangement")) } action: {
                        frames.primary = $0
                    }
            } secondary: {
                Color.clear
                    .frame(width: 100, height: 100)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("arrangement")) } action: {
                        frames.secondary = $0
                    }
                Color.clear
                    .frame(height: 20)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("arrangement")) } action: {
                        frames.accessory = $0
                    }
            }
            .arrangementViewStyle(.adaptive)
            .coordinateSpace(.named("arrangement"))
            .frame(width: size.width, height: size.height)
        )
        defer { hosted.close() }
        #expect(try await hosted.appears())
        let deadline = ContinuousClock.now + .seconds(5)
        while frames.accessory == nil || frames.secondary == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return frames
    }

    @Test func `Stacked, the second view sits under the keys at their width`() async throws {
        let frames = try await arrange(in: CGSize(width: 300, height: 600))
        let secondary = try #require(frames.secondary)
        let accessory = try #require(frames.accessory)

        #expect(accessory.minY > secondary.maxY)
        #expect(accessory.width == secondary.width)
        #expect(accessory.midX == secondary.midX)
    }

    @Test func `Side by side, the second view moves under the primary region at the keys' width`() async throws {
        let frames = try await arrange(in: CGSize(width: 600, height: 120))
        let primary = try #require(frames.primary)
        let secondary = try #require(frames.secondary)
        let accessory = try #require(frames.accessory)

        #expect(accessory.maxX <= secondary.minX)
        #expect(accessory.minY >= primary.maxY)
        #expect(accessory.width == secondary.width)
    }
}
