import WebKit

/// Blocks every network load from message bodies until the reader asks for remote content.
final class RemoteContentBlocker {
    static let shared = RemoteContentBlocker()
    /// The one compile in progress or done, which every caller waits on; cleared when it fails, so the next one tries
    /// again. The page's content security policy blocks remote loads meanwhile.
    private var compiling: Task<WKContentRuleList?, Never>?

    /// Compiles the rule list ahead of the first message that needs it.
    func prepare() {
        guard compiling == nil else { return }
        compiling = Task {
            let rules = #"[{"trigger":{"url-filter":"^(https?|ftp|wss?):"},"action":{"type":"block"}}]"#
            return try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "goodmail-block-remote", encodedContentRuleList: rules)
        }
    }

    func ruleList() async -> WKContentRuleList? {
        prepare()
        let list = await compiling?.value
        if list == nil { compiling = nil }
        return list
    }
}
