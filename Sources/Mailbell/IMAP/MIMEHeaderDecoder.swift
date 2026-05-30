import Foundation

/// Best-effort RFC 2047 decoder for encoded-words in headers, e.g.
/// `=?UTF-8?B?...?=` and `=?UTF-8?Q?...?=`. Falls back to the raw text.
enum MIMEHeaderDecoder {
    static func decode(_ input: String) -> String {
        guard input.contains("=?") else { return input }

        var result = ""
        var remainder = Substring(input)

        while let start = remainder.range(of: "=?") {
            result += remainder[remainder.startIndex..<start.lowerBound]
            let afterStart = remainder[start.upperBound...]
            guard let end = afterStart.range(of: "?=") else {
                result += remainder[start.lowerBound...]
                remainder = Substring("")
                break
            }
            let token = afterStart[afterStart.startIndex..<end.lowerBound]
            if let decoded = decodeWord(String(token)) {
                result += decoded
            } else {
                result += "=?" + token + "?="
            }
            remainder = afterStart[end.upperBound...]
        }
        result += remainder
        return result.isEmpty ? input : result
    }

    private static func decodeWord(_ token: String) -> String? {
        // token = charset?encoding?text
        let parts = token.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let charset = String(parts[0])
        let encoding = parts[1].uppercased()
        let text = String(parts[2])
        let stringEncoding = encodingFor(charset)

        switch encoding {
        case "B":
            guard let data = Data(base64Encoded: text) else { return nil }
            return String(data: data, encoding: stringEncoding)
        case "Q":
            return decodeQ(text, encoding: stringEncoding)
        default:
            return nil
        }
    }

    private static func decodeQ(_ text: String, encoding: String.Encoding) -> String? {
        var bytes = [UInt8]()
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "_" {
                bytes.append(0x20)
                index += 1
            } else if character == "=", index + 2 < chars.count,
                      let highNibble = chars[index + 1].hexDigitValue,
                      let lowNibble = chars[index + 2].hexDigitValue {
                bytes.append(UInt8(highNibble * 16 + lowNibble))
                index += 3
            } else {
                bytes.append(contentsOf: Array(String(character).utf8))
                index += 1
            }
        }
        return String(data: Data(bytes), encoding: encoding)
    }

    private static func encodingFor(_ charset: String) -> String.Encoding {
        switch charset.uppercased() {
        case "UTF-8", "UTF8": return .utf8
        case "ISO-8859-1", "LATIN1": return .isoLatin1
        case "US-ASCII", "ASCII": return .ascii
        default: return .utf8
        }
    }
}
