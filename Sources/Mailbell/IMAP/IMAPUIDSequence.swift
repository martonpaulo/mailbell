import Foundation

/// Turning a set of UIDs into IMAP sequence sets, and splitting them into
/// commands a server will accept. Pure formatting, kept out of the client so
/// the client is about the conversation rather than its punctuation.
enum IMAPUIDSequence {
    /// Gmail rejects very long command lines, so a bulk action is split by both
    /// UID count and rendered length rather than sent as one command.
    static let maximumUIDsPerCommand = 100
    static let maximumSequenceSetLength = 1500

    static func uidSequenceSet(for uids: [Int]) -> String {
        let sortedUIDs = Array(Set(uids.filter { $0 > 0 })).sorted()
        guard let first = sortedUIDs.first else { return "" }

        var ranges: [String] = []
        var start = first
        var previous = first

        for uid in sortedUIDs.dropFirst() {
            if uid == previous + 1 {
                previous = uid
                continue
            }
            ranges.append(sequenceRange(start: start, end: previous))
            start = uid
            previous = uid
        }

        ranges.append(sequenceRange(start: start, end: previous))
        return ranges.joined(separator: ",")
    }

    static func uidFetchBatches(for uids: [Int]) -> [[Int]] {
        let sortedUIDs = Array(Set(uids.filter { $0 > 0 })).sorted()
        var batches: [[Int]] = []
        var current: [Int] = []

        for uid in sortedUIDs {
            let candidate = current + [uid]
            if !current.isEmpty,
               candidate.count > maximumUIDsPerCommand
               || uidSequenceSet(for: candidate).count > maximumSequenceSetLength {
                batches.append(current)
                current = [uid]
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private static func sequenceRange(start: Int, end: Int) -> String {
        start == end ? "\(start)" : "\(start):\(end)"
    }
}
