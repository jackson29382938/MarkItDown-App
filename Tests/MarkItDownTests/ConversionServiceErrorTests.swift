import XCTest
@testable import MarkItDown

final class ConversionServiceErrorTests: XCTestCase {
    func testDetectsPythonPermissionError() {
        let error = ConversionServiceError.conversionFailed(
            message: "PermissionError: [Errno 1] Operation not permitted",
            debugOutput: "Traceback\nPermissionError: [Errno 1] Operation not permitted: '/Mail Downloads/file.md'"
        )

        XCTAssertTrue(error.isOutputPermissionError)
    }
}
