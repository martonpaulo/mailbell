import Foundation

/// Marketing mail pads its preheader with invisible characters so the inbox
/// snippet stays short. Those runs are not whitespace, so collapsing spaces
/// leaves them in place and they consume the whole preview budget — which is
/// what reached notifications as unreadable filler.
///
/// A run is padding; a single joiner is language. One ZWJ between pictographs
/// builds an emoji, and one ZWNJ between letters is meaningful in Persian and
/// the Indic scripts, so only runs are removed.
enum PreviewNoiseNormalizer {
    /// Format and zero-width characters used as padding, plus the fixed-width
    /// spaces that behave the same way.
    private static let invisibleScalars: Set<Unicode.Scalar> = [
        "\u{00ad}", // soft hyphen
        "\u{034f}", // combining grapheme joiner
        "\u{200b}", // zero-width space
        "\u{200c}", // zero-width non-joiner
        "\u{200d}", // zero-width joiner
        "\u{200e}", "\u{200f}", // directional marks
        "\u{2060}", // word joiner
        "\u{feff}" // zero-width no-break space
    ]

    private static let paddingSpaceScalars: Set<Unicode.Scalar> = [
        "\u{00a0}", // no-break space
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}",
        "\u{200a}", "\u{202f}", "\u{205f}", "\u{3000}"
    ]

    static func removePaddingRuns(from text: String) -> String {
        var result = String.UnicodeScalarView()
        var run: [Unicode.Scalar] = []
        var invisibleCountInRun = 0

        func flushRun() {
            defer {
                run.removeAll()
                invisibleCountInRun = 0
            }
            // One invisible scalar is a joiner doing its job; keep the run as
            // written. Two or more is stuffing.
            guard invisibleCountInRun > 1 else {
                result.append(contentsOf: run)
                return
            }
            result.append(" ")
        }

        for scalar in text.unicodeScalars {
            if invisibleScalars.contains(scalar) {
                run.append(scalar)
                invisibleCountInRun += 1
                continue
            }
            // Ordinary and fixed-width spaces sit between padding characters
            // without ending the run.
            if !run.isEmpty, scalar == " " || paddingSpaceScalars.contains(scalar) {
                run.append(scalar)
                continue
            }
            flushRun()
            result.append(scalar)
        }
        flushRun()

        return String(result)
    }

    /// "View online" boilerplate is the first thing in many campaigns, so the
    /// preview opens on a marker instead of the message. Only leading markers
    /// go, and only when readable text follows them.
    static func removeLeadingLinkBoilerplate(from text: String, urlMarker: String) -> String {
        var remainder = Substring(text)

        while true {
            let trimmed = remainder.drop(while: { $0 == " " })
            guard trimmed.hasPrefix(urlMarker) else { break }
            let candidate = trimmed.dropFirst(urlMarker.count)
            // Keep the marker when it is all the preview has to show.
            guard candidate.contains(where: { !$0.isWhitespace }) else { break }
            remainder = candidate
        }

        return String(remainder).trimmingCharacters(in: .whitespaces)
    }
}
