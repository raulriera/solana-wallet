import Redaction
import Testing

struct RedactedTests {
    private struct Secret: Redacted {
        let value = "fixture-secret"
    }

    private struct Renamed: Redacted {
        let value = "fixture-secret"

        var description: String { "Outer.Renamed" }
    }

    @Test
    func `Descriptions and dumps show only the type name`() {
        var dumped = ""
        dump(Secret(), to: &dumped)

        #expect(String(describing: Secret()) == "Secret")
        #expect(String(reflecting: Secret()) == "Secret")
        #expect(dumped == "- Secret\n")
    }

    @Test
    func `A custom description also names debug descriptions and dumps`() {
        var dumped = ""
        dump(Renamed(), to: &dumped)

        #expect(String(reflecting: Renamed()) == "Outer.Renamed")
        #expect(dumped == "- Outer.Renamed\n")
    }
}
