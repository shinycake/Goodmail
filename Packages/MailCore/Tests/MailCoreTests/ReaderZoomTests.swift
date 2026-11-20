import MailCore
import Testing

struct ReaderZoomTests {
    @Test("The standard size is 100 percent, and it is where an unset or unknown value lands")
    func standard() {
        #expect(ReaderZoom.standard.factor == 1)
        #expect(ReaderZoom(stored: nil) == .standard)
        #expect(ReaderZoom(stored: .nan) == .standard)
        #expect(ReaderZoom(stored: -3) == .standard)
    }

    @Test("A stored factor snaps to the nearest step")
    func snaps() {
        #expect(ReaderZoom(stored: 1.26).factor == 1.25)
        #expect(ReaderZoom(stored: 99).factor == ReaderZoom.steps.last)
        #expect(ReaderZoom(stored: 0.01).factor == ReaderZoom.steps.first)
    }

    @Test("Zooming in and out walks the steps and stops at their ends")
    func walks() {
        var zoom = ReaderZoom.standard
        zoom = zoom.zoomedIn()
        #expect(zoom.factor == 1.1)
        zoom = zoom.zoomedOut().zoomedOut()
        #expect(zoom.factor == 0.9)
        for _ in 0..<50 { zoom = zoom.zoomedIn() }
        #expect(!zoom.canZoomIn)
        #expect(zoom.canZoomOut)
        #expect(zoom.zoomedIn() == zoom)
        for _ in 0..<50 { zoom = zoom.zoomedOut() }
        #expect(!zoom.canZoomOut)
        #expect(zoom.zoomedOut() == zoom)
    }

    @Test("Only the standard step is standard")
    func isStandard() {
        #expect(ReaderZoom.standard.isStandard)
        #expect(!ReaderZoom.standard.zoomedIn().isStandard)
    }
}
