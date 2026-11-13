import Testing

@testable import MailCore

@MainActor
struct TaskChainTests {
    @Test func workRunsInTheOrderItWasAskedForEvenWhenEarlierWorkWaitsLonger() async {
        let chain = TaskChain()
        var done: [String] = []
        chain.run {
            try? await Task.sleep(for: .milliseconds(50))
            done.append("slow, first")
        }
        chain.run { done.append("quick, second") }
        chain.run {
            await Task.yield()
            done.append("third")
        }
        await chain.settled()
        #expect(done == ["slow, first", "quick, second", "third"])
    }

    @Test func settledWaitsForWorkAskedForBeforeIt() async {
        let chain = TaskChain()
        var finished = false
        chain.run {
            try? await Task.sleep(for: .milliseconds(20))
            finished = true
        }
        await chain.settled()
        #expect(finished)
    }

    @Test func anEmptyChainIsSettled() async {
        await TaskChain().settled()
    }
}
