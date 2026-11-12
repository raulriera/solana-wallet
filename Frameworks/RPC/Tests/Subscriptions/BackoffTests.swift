import RPC
import Testing

struct BackoffTests {
    @Test
    func `Waits double after each attempt up to the longest wait`() {
        var backoff = Backoff(first: .seconds(2), longest: .seconds(10))

        let waits = (0..<5).map { _ in backoff.next() }

        #expect(waits == [.seconds(2), .seconds(4), .seconds(8), .seconds(10), .seconds(10)])
    }

    @Test
    func `A reset starts over from the first wait`() {
        var backoff = Backoff(first: .seconds(2), longest: .seconds(10))
        _ = backoff.next()
        _ = backoff.next()

        backoff.reset()

        #expect(backoff.next() == .seconds(2))
    }
}
