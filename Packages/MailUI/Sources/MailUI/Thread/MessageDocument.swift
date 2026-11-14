import Foundation
import MailCore

/// Turns a message body into the HTML document its web view loads. Pure, so the RTL and quoting rules are testable.
nonisolated enum MessageDocument {
    /// HTML bodies keep their markup; plain-text bodies become HTML with one block per line and `>` quotes nested.
    /// Our stylesheet and viewport go first in the head, so the sender's own styles still win where they set any.
    /// Until the reader allows remote content, a content security policy leads the head and blocks it (ADR-003).
    /// The web view also blocks it with a content rule list, but that has to compile first, and if it ever fails
    /// the policy still holds: the block fails closed.
    /// The palette decides how the body's colors meet light and dark appearance; the script reads it from the head.
    static func html(for body: MessageBody, palette: MessagePalette, allowsRemoteContent: Bool) -> String {
        let head =
            (allowsRemoteContent ? "" : remoteContentPolicy) + baseHead
            + #"<meta name="goodmail-palette" content="\#(palette.rawValue)">"# + palette.style
        if let html = body.html, !html.isEmpty {
            return inject(head: head, into: html)
        }
        return "<!doctype html><html><head>\(head)\(plainStyle)</head><body>\(plainToHTML(body.plain ?? ""))"
            + "</body></html>"
    }

    /// Loads only what the message carries itself: `cid:` parts and `data:` URLs. Inline styles stay, so the
    /// sender's layout and ours both apply. Our script runs in its own content world, which the policy doesn't touch.
    static let remoteContentPolicy =
        #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; "#
        + #"img-src cid: data:; media-src cid: data:; font-src cid: data:; style-src 'unsafe-inline' cid: data:">"#

    /// Each line is its own `dir=auto` block, so a Hebrew line and an English line each read and align their own way.
    /// Lines starting with `>` nest into blockquotes by depth.
    static func plainToHTML(_ text: String) -> String {
        var html = ""
        var depth = 0
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            var line = Substring(rawLine)
            var level = 0
            while let first = line.first, first == ">" {
                level += 1
                line = line.dropFirst()
                if line.first == " " { line = line.dropFirst() }
            }
            while depth < level {
                html += #"<blockquote class="goodmail-quote">"#
                depth += 1
            }
            while depth > level {
                html += "</blockquote>"
                depth -= 1
            }
            html += line.isEmpty ? "<br>" : #"<div dir="auto">\#(escape(String(line)))</div>"#
        }
        html += String(repeating: "</blockquote>", count: depth)
        return html
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Inserts `head` at the start of the document's `<head>`, creating one when the sender's HTML has none.
    static func inject(head: String, into html: String) -> String {
        if let range = html.range(of: #"<head(\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: range, with: html[range] + head)
        }
        if let range = html.range(of: #"<html(\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: range, with: html[range] + "<head>\(head)</head>")
        }
        return "<!doctype html><html><head>\(head)</head><body>\(html)</body></html>"
    }

    /// The quote fold draws a 22 pt pill, and its transparent border grows the tap area to 44 pt around it.
    private static let baseHead = """
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">\
        <style>\
        html { -webkit-text-size-adjust: 100%; }\
        body { margin: 0; overflow-wrap: anywhere; }\
        img { max-width: 100%; height: auto; }\
        :where(body) { font: -apple-system-body; line-height: 1.4; }\
        :where(a) { color: light-dark(#0066cc, #409cff); }\
        details.goodmail-fold > summary { list-style: none; display: inline-block; margin: -3px 0; \
        margin-inline-start: -11px; padding: 0 10px; border: 11px solid transparent; background-clip: padding-box; \
        border-radius: 21px; background-color: rgba(120,120,128,0.16); color: light-dark(#636366, #a1a1a6); \
        font: 600 15px/22px -apple-system; cursor: pointer; }\
        details.goodmail-fold > summary::-webkit-details-marker { display: none; }\
        </style>
        """

    /// Plain text gets the reading typography of the app, the system font at the body size. Its palette is adaptive.
    private static let plainStyle = """
        <style>\
        body { font: -apple-system-body; line-height: 1.45; }\
        blockquote.goodmail-quote { margin: 0; padding-inline-start: 10px; border-inline-start: 2px solid \
        rgba(120,120,128,0.4); color: light-dark(#636366, #a1a1a6); }\
        </style>
        """
}
