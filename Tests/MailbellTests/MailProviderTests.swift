@testable import mailbell
import XCTest

final class MailProviderTests: XCTestCase {
    func testGmailProviderUsesGenericWebmailURL() {
        let provider = MailProviderRegistry.provider(for: .gmail)

        XCTAssertEqual(provider.webmailURL.absoluteString, "https://mail.google.com/")
        XCTAssertEqual(provider.capabilities.supportsThreadLink, false)
    }
}
