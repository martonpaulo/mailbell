import Foundation
import Network

/// A line-oriented IMAP transport over implicit TLS (port 993).
///
/// Provides `readLine` for CRLF-terminated protocol lines and `readBytes` for
/// IMAP literals (`{n}`). All reads are fed from a single buffer that is topped
/// up from the network as needed.
final class IMAPConnection {
    enum ConnectionError: Error {
        case notReady(String)
        case closed
        case timedOut
    }

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.samzong.mailbell.imap")
    private var buffer = Data()

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let tls = NWProtocolTLS.Options()
        let params = NWParameters(tls: tls)
        self.connection = NWConnection(host: self.host, port: self.port, using: params)
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let error):
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                case .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: ConnectionError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    func send(_ line: String) async throws {
        try await sendRaw(line + "\r\n")
    }

    func sendRaw(_ text: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// Returns the next CRLF-terminated line (without the trailing CRLF).
    func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(bytes: lineData, encoding: .utf8) ?? ""
            }
            try await fill()
        }
    }

    /// Reads exactly `count` bytes (for IMAP literals).
    func readBytes(_ count: Int) async throws -> Data {
        while buffer.count < count {
            try await fill()
        }
        let chunk = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(chunk)
    }

    private func fill() async throws {
        let data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: ConnectionError.closed)
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
        buffer.append(data)
    }
}
