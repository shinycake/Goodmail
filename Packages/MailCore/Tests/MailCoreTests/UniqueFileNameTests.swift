import MailCore
import Testing

struct UniqueFileNameTests {
    @Test("A free name is kept")
    func free() {
        #expect(UniqueFileName.choosing("report.pdf", taken: { _ in false }) == "report.pdf")
    }

    @Test("A taken name gets the next number before its extension, as the Finder numbers copies")
    func numbered() {
        let taken: Set<String> = ["report.pdf", "report 2.pdf"]
        #expect(UniqueFileName.choosing("report.pdf", taken: taken.contains) == "report 3.pdf")
    }

    @Test("A name without an extension, and a dotfile, are numbered at the end")
    func noExtension() {
        #expect(UniqueFileName.choosing("README", taken: ["README"].contains) == "README 2")
        #expect(UniqueFileName.choosing(".env", taken: [".env"].contains) == ".env 2")
    }

    @Test("Only the last extension is kept apart")
    func lastExtension() {
        #expect(UniqueFileName.choosing("a.tar.gz", taken: ["a.tar.gz"].contains) == "a.tar 2.gz")
    }
}
