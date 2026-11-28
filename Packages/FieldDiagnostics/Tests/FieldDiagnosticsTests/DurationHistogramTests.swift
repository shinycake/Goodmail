import FieldDiagnostics
import Foundation
import Testing

/// Launch, resume and hang times come as histograms; the screen reads the typical and the slow ends of them.
struct DurationHistogramTests {
    private typealias Bucket = DurationHistogram.Bucket

    @Test func anEmptyHistogramHasNoPercentiles() {
        let empty = DurationHistogram([Bucket(start: 0, end: 0.1, count: 0)])
        #expect(empty.count == 0)
        #expect(empty.buckets.isEmpty, "buckets with nothing in them are dropped")
        #expect(empty.percentile(0.5) == nil)
    }

    /// Within a bucket the times are taken to spread evenly, so the median of one bucket is its middle.
    @Test func aPercentileFallsWithinItsBucket() {
        let one = DurationHistogram([Bucket(start: 0.25, end: 0.75, count: 10)])
        #expect(one.percentile(0.5) == 0.5)
        #expect(one.percentile(1) == 0.75)
    }

    @Test func aDecodedHistogramKeepsItsOrder() throws {
        let json =
            #"{"buckets":[{"start":0.5,"end":1,"count":1},{"start":0,"end":0.5,"count":0},"#
            + #"{"start":0.1,"end":0.5,"count":3}]}"#
        let histogram = try JSONDecoder().decode(DurationHistogram.self, from: Data(json.utf8))
        #expect(histogram.buckets.map(\.start) == [0.1, 0.5])
    }

    @Test(arguments: [
        (0.5, 0.15),  // the 10th of 20 is the 5th of the second bucket's 10
        (0.9, 0.9),  // the 18th of 20: the last of the third bucket, at its end
        (0.25, 0.1),  // the 5th of 20: the last of the fastest bucket
    ])
    func percentilesAcrossBuckets(fraction: Double, expected: Double) throws {
        let histogram = DurationHistogram([
            Bucket(start: 0.5, end: 0.9, count: 3),
            Bucket(start: 0, end: 0.1, count: 5),
            Bucket(start: 0.1, end: 0.2, count: 10),
            Bucket(start: 0.2, end: 0.5, count: 0),
            Bucket(start: 0.9, end: 2, count: 2),
        ])
        #expect(histogram.count == 20)
        #expect(histogram.buckets.map(\.start) == [0, 0.1, 0.5, 0.9], "in order, the empty bucket dropped")
        let value = try #require(histogram.percentile(fraction))
        #expect(abs(value - expected) < 1e-9)
    }
}
