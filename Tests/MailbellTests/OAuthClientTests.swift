@testable import mailbell
import XCTest

final class OAuthClientTests: XCTestCase {
    private let clientID = "dummy-local-client-id.apps.googleusercontent.com"
    private let clientSecret = "dummy-local-client-secret"

    override func tearDown() {
        OAuthURLProtocolMock.handler = nil
        super.tearDown()
    }

    func testRefreshTokenRequestIncludesClientSecretWhenConfigured() async throws {
        let recorder = OAuthRequestRecorder()
        OAuthURLProtocolMock.handler = { request in
            recorder.record(request)
            return .json(statusCode: 200, body: Self.tokenResponseJSON)
        }
        let client = OAuthClient(config: config(clientSecret: clientSecret), session: mockSession())

        _ = try await client.refresh(refreshToken: "refresh-value")

        let body = try XCTUnwrap(recorder.lastBody)
        XCTAssertTrue(body.contains("client_secret= dummy") == false)
        XCTAssertTrue(body.contains("client_secret=dummy-local-client-secret"))
        XCTAssertTrue(body.contains("refresh_token=refresh-value"))
    }

    func testRefreshTokenRequestOmitsClientSecretWhenAbsent() async throws {
        let recorder = OAuthRequestRecorder()
        OAuthURLProtocolMock.handler = { request in
            recorder.record(request)
            return .json(statusCode: 200, body: Self.tokenResponseJSON)
        }
        let client = OAuthClient(config: config(clientSecret: nil), session: mockSession())

        _ = try await client.refresh(refreshToken: "refresh-value")

        let body = try XCTUnwrap(recorder.lastBody)
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertTrue(body.contains("client_id=\(clientID)"))
        XCTAssertTrue(body.contains("refresh_token=refresh-value"))
    }

    func testAuthorizationCodeExchangeIncludesClientSecretWhenConfigured() async throws {
        let recorder = OAuthRequestRecorder()
        OAuthURLProtocolMock.handler = { request in
            recorder.record(request)
            if request.url?.host == "oauth2.googleapis.com" {
                return .json(statusCode: 200, body: Self.tokenResponseJSON)
            }
            return .json(statusCode: 200, body: #"{"email":"account@example.com"}"#)
        }
        let client = OAuthClient(
            config: config(clientSecret: clientSecret),
            session: mockSession(),
            openBrowser: { url in
                Self.completeLoopback(url, query: "code=oauth-code")
                return true
            }
        )

        let result = try await client.signIn()

        XCTAssertEqual(result.email, "account@example.com")
        let body = try XCTUnwrap(recorder.bodies.first { $0.contains("grant_type=authorization_code") })
        XCTAssertTrue(body.contains("client_secret=dummy-local-client-secret"))
        XCTAssertTrue(body.contains("code=oauth-code"))
    }

    func testAuthorizationCodeExchangeOmitsClientSecretWhenAbsent() async throws {
        let recorder = OAuthRequestRecorder()
        OAuthURLProtocolMock.handler = { request in
            recorder.record(request)
            if request.url?.host == "oauth2.googleapis.com" {
                return .json(statusCode: 200, body: Self.tokenResponseJSON)
            }
            return .json(statusCode: 200, body: #"{"email":"account@example.com"}"#)
        }
        let client = OAuthClient(
            config: config(clientSecret: nil),
            session: mockSession(),
            openBrowser: { url in
                Self.completeLoopback(url, query: "code=oauth-code")
                return true
            }
        )

        _ = try await client.signIn()

        let body = try XCTUnwrap(recorder.bodies.first { $0.contains("grant_type=authorization_code") })
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertTrue(body.contains("code=oauth-code"))
    }

    func testProviderDenialMapsToAuthorizationDeniedWithoutTokenRequest() async throws {
        let client = OAuthClient(
            config: config(clientSecret: nil),
            session: mockSession(),
            openBrowser: { url in
                Self.completeLoopback(url, query: "error=access_denied")
                return true
            }
        )

        do {
            _ = try await client.signIn()
            XCTFail("Expected provider denial to throw.")
        } catch let error as OAuthClient.OAuthError {
            XCTAssertEqual(error, .authorizationDenied("access_denied"))
        }
    }

    func testBrowserOpenFailureStopsLoopbackServer() async throws {
        let server = LoopbackServer()
        let client = OAuthClient(
            config: config(clientSecret: nil),
            session: mockSession(),
            openBrowser: { _ in false },
            loopbackServerFactory: { server }
        )

        do {
            _ = try await client.signIn()
            XCTFail("Expected browser-open failure.")
        } catch let error as OAuthClient.OAuthError {
            XCTAssertEqual(error, .browserOpenFailed)
        }

        let port = await server.port
        XCTAssertEqual(port, 0)
    }

    func testInvalidGrantRefreshFailureIsTerminal() async {
        OAuthURLProtocolMock.handler = { _ in
            .json(statusCode: 400, body: #"{"error":"invalid_grant"}"#)
        }
        let client = OAuthClient(config: config(clientSecret: nil), session: mockSession())

        do {
            _ = try await client.refresh(refreshToken: "refresh-value")
            XCTFail("Expected terminal refresh failure.")
        } catch let error as OAuthClient.OAuthError {
            XCTAssertEqual(error, .refreshFailed("OAuth token endpoint returned invalid_grant (HTTP 400)."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerRefreshFailureRemainsTransient() async {
        OAuthURLProtocolMock.handler = { _ in
            .json(statusCode: 500, body: #"{"error":"server_error"}"#)
        }
        let client = OAuthClient(config: config(clientSecret: nil), session: mockSession())

        do {
            _ = try await client.refresh(refreshToken: "refresh-value")
            XCTFail("Expected transient refresh failure.")
        } catch let error as OAuthClient.OAuthError {
            XCTAssertEqual(error, .refreshUnavailable("OAuth token endpoint returned server_error (HTTP 500)."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTokenEndpointDetailOmitsRawResponseDescriptionAndSecrets() {
        let description = [
            "client_secret=secret-value",
            "refresh_token=refresh-value",
            "access_token=access-value",
            "code=oauth-code"
        ].joined(separator: " ")
        let body = """
        {
          "error": "invalid_grant",
          "error_description": "\(description)"
        }
        """

        let detail = OAuthClient.sanitizedTokenEndpointDetail(statusCode: 400, body: body)

        XCTAssertEqual(detail, "OAuth token endpoint returned invalid_grant (HTTP 400).")
        XCTAssertFalse(detail.contains("secret-value"))
        XCTAssertFalse(detail.contains("refresh-value"))
        XCTAssertFalse(detail.contains("access-value"))
        XCTAssertFalse(detail.contains("oauth-code"))
    }

    func testTokenEndpointDetailFallsBackToStatusOnlyForNonJSONBody() {
        let detail = OAuthClient.sanitizedTokenEndpointDetail(
            statusCode: 500,
            body: "server client_secret=secret-value"
        )

        XCTAssertEqual(detail, "OAuth token endpoint returned HTTP 500.")
        XCTAssertFalse(detail.contains("secret-value"))
    }

    func testTokenEndpointDetailDoesNotEchoUnexpectedErrorCodeText() {
        let detail = OAuthClient.sanitizedTokenEndpointDetail(
            statusCode: 400,
            body: #"{"error":"invalid_grant client_secret=secret-value"}"#
        )

        XCTAssertEqual(detail, "OAuth token endpoint returned HTTP 400.")
        XCTAssertFalse(detail.contains("secret-value"))
        XCTAssertFalse(detail.contains("invalid_grant client_secret"))
    }

    func testUserInfoEndpointDetailUsesStatusOnly() {
        let detail = OAuthClient.sanitizedUserInfoDetail(statusCode: 429)

        XCTAssertEqual(detail, "OpenID UserInfo endpoint returned HTTP 429.")
        XCTAssertFalse(detail.contains("access_token"))
        XCTAssertFalse(detail.contains("Bearer"))
    }

    func testRandomURLSafeStringThrowsWhenSecureRandomFails() {
        XCTAssertThrowsError(
            try OAuthClient.randomURLSafeString(
                count: 24,
                copyRandomBytes: { _, _ in errSecAllocate }
            )
        ) { error in
            XCTAssertEqual(error as? OAuthClient.OAuthError, .secureRandomUnavailable)
            XCTAssertEqual(error.localizedDescription, "Could not create secure OAuth state. Try again.")
        }
    }

    func testRandomURLSafeStringRejectsEmptyOutput() {
        XCTAssertThrowsError(try OAuthClient.randomURLSafeString(count: 0)) { error in
            XCTAssertEqual(error as? OAuthClient.OAuthError, .secureRandomUnavailable)
        }
    }

    private func config(clientSecret: String?) -> OAuthConfig {
        OAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocolMock.self]
        return URLSession(configuration: configuration)
    }

    private static var tokenResponseJSON: String {
        """
        {
          "access_token": "access-value",
          "expires_in": 3600,
          "refresh_token": "refresh-value",
          "token_type": "Bearer",
          "scope": "email openid https://mail.google.com/"
        }
        """
    }

    @MainActor
    private static func completeLoopback(_ authURL: URL, query: String) {
        let callbackURL = callbackURL(from: authURL, appendingQuery: query)
        Task {
            _ = try? await URLSession.shared.data(from: callbackURL)
        }
    }

    private static func callbackURL(from authURL: URL, appendingQuery query: String) -> URL {
        let authComponents = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        let redirect = authComponents?.queryItems?.first(where: { $0.name == "redirect_uri" })?.value
        let state = authComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        var callbackComponents = URLComponents(string: redirect!)!
        callbackComponents.queryItems = [
            URLQueryItem(name: "state", value: state)
        ]
        let extraItems = query.split(separator: "&").map { pair -> URLQueryItem in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return URLQueryItem(name: parts[0], value: parts.count == 2 ? parts[1] : "")
        }
        callbackComponents.queryItems?.append(contentsOf: extraItems)
        return callbackComponents.url!
    }
}

private final class OAuthRequestRecorder {
    private let lock = NSLock()
    private var recordedBodies: [String] = []

    var bodies: [String] {
        lock.withLock { recordedBodies }
    }

    var lastBody: String? {
        lock.withLock { recordedBodies.last }
    }

    func record(_ request: URLRequest) {
        let body = Self.bodyString(from: request)
        lock.withLock {
            recordedBodies.append(body)
        }
    }

    private static func bodyString(from request: URLRequest) -> String {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class OAuthURLProtocolMock: URLProtocol {
    struct Response {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        static func json(statusCode: Int, body: String) -> Response {
            Response(
                statusCode: statusCode,
                data: Data(body.utf8),
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    private static let handlerBox = OAuthURLProtocolHandlerBox<Response>()

    static var handler: ((URLRequest) throws -> Response)? {
        get { handlerBox.handler }
        set { handlerBox.handler = newValue }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// Test-only shared URLProtocol state; all reads and writes are serialized by `lock`.
private final class OAuthURLProtocolHandlerBox<Response>: @unchecked Sendable {
    private let lock = NSLock()
    private var requestHandler: ((URLRequest) throws -> Response)?

    var handler: ((URLRequest) throws -> Response)? {
        get { lock.withLock { requestHandler } }
        set { lock.withLock { requestHandler = newValue } }
    }
}
