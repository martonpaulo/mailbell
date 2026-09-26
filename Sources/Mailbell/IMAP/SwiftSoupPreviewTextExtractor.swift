import Foundation
import SwiftSoup

/// Turning an HTML message part into plain preview text: dropping the parts a
/// reader never sees and marking images. The preview sanitizer in MailbellKit
/// takes this as its HTML extractor; it lives in the app target because the
/// Kit never imports SwiftSoup (#80).
///
/// Nonisolated: called by IMAPClient inside MailMonitor run tasks.
nonisolated enum SwiftSoupPreviewTextExtractor {
    private static let imageMarker = "[IMG]"

    static func extractText(from text: String) throws -> String {
        let document = try SwiftSoup.parseHTML(text)
        try document.select("script, style, noscript, template, head, meta, link").remove()
        try document.select("[hidden], [aria-hidden=true]").remove()

        for element in try document.select("[style]").array() {
            let style = try element.attr("style")
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            if style.contains("display:none")
                || style.contains("visibility:hidden")
                || style.contains("opacity:0")
            {
                try element.remove()
            }
        }

        for element in try document.select("img, svg").array() {
            try element.before(" \(imageMarker) ")
            try element.remove()
        }

        if let body = document.body() {
            return try body.text()
        }
        return try document.text()
    }
}
