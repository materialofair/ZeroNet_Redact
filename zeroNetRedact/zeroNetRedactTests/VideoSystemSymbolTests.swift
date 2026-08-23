import UIKit
import XCTest

final class VideoSystemSymbolTests: XCTestCase {
    func testVideoEditorSystemSymbolsExist() {
        let symbols = [
            "rectangle.landscape.rotate",
            "rectangle",
            "checkmark.shield.fill",
        ]

        for symbol in symbols {
            XCTAssertNotNil(UIImage(systemName: symbol), "不存在的 SF Symbol：\(symbol)")
        }
    }
}
