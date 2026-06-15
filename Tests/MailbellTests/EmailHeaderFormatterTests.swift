@testable import mailbell
import XCTest

final class EmailHeaderFormatterTests: XCTestCase {
    func testSenderIdentitySeparatesDisplayNameAndAddress() {
        let sender = EmailHeaderFormatter.senderIdentity(
            from: "\"Contabilizei Contabilidade Online\" <mensalidade@contabilizei.com.br>"
        )

        XCTAssertEqual(sender.name, "Contabilizei Contabilidade Online")
        XCTAssertEqual(sender.address, "mensalidade@contabilizei.com.br")
    }

    func testSenderIdentityKeepsPlainSenderWithoutDuplicateAddress() {
        let sender = EmailHeaderFormatter.senderIdentity(from: "Newsletter")

        XCTAssertEqual(sender.name, "Newsletter")
        XCTAssertNil(sender.address)
    }
}
