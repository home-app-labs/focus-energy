import XCTest
import CryptoKit
@testable import FocusPlus

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateRules.isNewer("1.1.0", than: "1.0.9"))
        XCTAssertTrue(UpdateRules.isNewer("1.10.0", than: "1.9.3"))
        XCTAssertTrue(UpdateRules.isNewer("2.0", than: "1.99.99"))
        XCTAssertTrue(UpdateRules.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateRules.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(UpdateRules.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(UpdateRules.isNewer("1.0.9", than: "1.1.0"), "never go back to an older version")
        XCTAssertFalse(UpdateRules.isNewer("latest", than: "1.0.0"))
        XCTAssertFalse(UpdateRules.isNewer("2.0-beta", than: "1.0.0"))
        XCTAssertFalse(UpdateRules.isNewer("", than: "1.0.0"))
    }

    func testOnlyUpdatesSignedWithTheRightKeyPass() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let zip = Data("pretend this is a zipped app".utf8)
        let signature = try key.signature(for: zip).base64EncodedString()

        XCTAssertTrue(UpdateRules.isSigned(zip, signature: signature, publicKey: publicKey))
        XCTAssertFalse(UpdateRules.isSigned(zip + Data([0]), signature: signature, publicKey: publicKey), "one byte changed")
        XCTAssertFalse(UpdateRules.isSigned(zip, signature: signature), "signed with a key that is not the Home App Labs one")
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: zip).base64EncodedString()
        XCTAssertFalse(UpdateRules.isSigned(zip, signature: stranger, publicKey: publicKey))
        XCTAssertFalse(UpdateRules.isSigned(zip, signature: "", publicKey: publicKey))
        XCTAssertFalse(UpdateRules.isSigned(zip, signature: "not base64 at all", publicKey: publicKey))
    }

    func testTheBuiltInKeyIsAValidPublicKey() throws {
        let raw = try XCTUnwrap(Data(base64Encoded: UpdateRules.publicKey))
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: raw))
    }

    func testManifestIsRead() throws {
        let json = #"{"version":"1.2.0","notes":"Better.","url":"https://example.org/app.zip","signature":"abc","size":123}"#
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.version, "1.2.0")
        XCTAssertEqual(manifest.size, 123)
    }
}
