import MailCore
import WebKit

/// Serves `cid:` URLs from the message's inline parts.
final class CIDSchemeHandler: NSObject, WKURLSchemeHandler {
    var message: Message?
    /// Fetches a part a `cid:` URL names; set by the view that takes the web view.
    var attachmentData: ((Attachment, Message.ID) async throws -> Data)?
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let contentID = (task.request.url?.absoluteString.dropFirst("cid:".count)).map(String.init)?
            .removingPercentEncoding
        guard let message, let attachmentData,
            let attachment = message.attachments.first(where: { $0.contentID == contentID })
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        running[key] = Task {
            defer { running[key] = nil }
            do {
                let data = try await attachmentData(attachment, message.id)
                guard !Task.isCancelled, let url = task.request.url else { return }
                task.didReceive(
                    URLResponse(
                        url: url, mimeType: attachment.mimeType, expectedContentLength: data.count,
                        textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            } catch {
                if !Task.isCancelled { task.didFailWithError(error) }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }
}
