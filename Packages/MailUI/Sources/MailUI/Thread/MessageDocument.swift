import Foundation
import MailCore

/// Turns a message body into the HTML document its web view loads. Pure, so the RTL and quoting rules are testable.
nonisolated enum MessageDocument {
    /// HTML bodies keep their markup; plain-text bodies become HTML with one block per line and `>` quotes nested.
    /// Our stylesheet and viewport go first in the head, so the sender's own styles still win where they set any.
    static func html(for body: MessageBody) -> String {
        if let html = body.html, !html.isEmpty {
            return inject(head: baseHead, into: html)
        }
        return "<!doctype html><html><head>\(baseHead)\(plainStyle)</head><body>\(plainToHTML(body.plain ?? ""))"
            + "</body></html>"
    }

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

    private static let baseHead = """
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">\
        <style>\
        html { -webkit-text-size-adjust: 100%; }\
        body { margin: 0; overflow-wrap: anywhere; }\
        img { max-width: 100%; height: auto; }\
        :where(body) { font: -apple-system-body; line-height: 1.4; }\
        :where(a) { color: #007aff; }\
        details.goodmail-fold > summary { list-style: none; display: inline-block; margin: 8px 0; padding: 0 10px; \
        border-radius: 10px; background: rgba(120,120,128,0.16); color: rgba(60,60,67,0.6); font: 600 15px/22px \
        -apple-system; cursor: pointer; }\
        details.goodmail-fold > summary::-webkit-details-marker { display: none; }\
        </style>
        """

    /// Plain text gets the reading typography of the app, New York at the body size, light and dark.
    private static let plainStyle = """
        <style>\
        :root { color-scheme: light dark; }\
        body { font: -apple-system-body; font-family: ui-serif, "New York", serif; line-height: 1.45; }\
        blockquote.goodmail-quote { margin: 0; padding-inline-start: 10px; border-inline-start: 2px solid \
        rgba(120,120,128,0.4); color: rgba(120,120,128,1); }\
        </style>
        """
}
