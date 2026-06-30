import Foundation
import XCTest
@testable import MarkItDown

final class EngineManifestTests: XCTestCase {
    func testDecodesManifest() throws {
        let data = """
        {
          "markitdownVersion": "0.1.6",
          "pythonVersion": "3.12",
          "createdAt": "2026-06-23T19:00:00Z",
          "installKind": "bundled"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(EngineManifest.self, from: data)

        XCTAssertEqual(manifest.markitdownVersion, "0.1.6")
        XCTAssertEqual(manifest.pythonVersion, "3.12")
        XCTAssertEqual(manifest.installKind, .bundled)
    }

    func testSemanticVersionComparisonIgnoresLeadingV() {
        XCTAssertLessThan(SemanticVersion("v0.1.5"), SemanticVersion("0.1.6"))
        XCTAssertGreaterThan(SemanticVersion("0.2.0"), SemanticVersion("0.1.99"))
        XCTAssertEqual(SemanticVersion("v1.0"), SemanticVersion("1.0.0"))
    }
}
