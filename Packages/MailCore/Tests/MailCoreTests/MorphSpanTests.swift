import MailCore
import Testing

struct MorphSpanTests {
    @Test("Mirrored, a span at the end of the motion moves to its start")
    func mirrorsEnd() {
        #expect(MorphSpan(start: 0.8, length: 0.2).mirrored == MorphSpan(start: 0, length: 0.2))
    }

    @Test(
        "Mirrored twice, every piece of the minimize is back where it was",
        arguments: [MinimizeMorph.shrink, MinimizeMorph.curtain, MinimizeMorph.composer])
    func mirrorsBack(span: MorphSpan) {
        #expect(span.mirrored.mirrored == span)
        #expect(span.mirrored.start + span.mirrored.length <= 1)
    }

    @Test("The composer gives way only after the curtain is gone, and reopening shows again before it comes back")
    func composerGoesLast() {
        #expect(MinimizeMorph.curtain.start + MinimizeMorph.curtain.length < MinimizeMorph.composer.start)
        #expect(MinimizeMorph.composer.mirrored.start < MinimizeMorph.curtain.mirrored.start)
    }
}
