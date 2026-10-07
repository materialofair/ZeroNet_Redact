import PDFKit
import UIKit
import Vision
import XCTest
@testable import zeroNetRedact

@MainActor
final class InternationalRecognitionTests: XCTestCase {
    private func matches(_ text: String, type: SensitiveType) -> [InternationalSensitiveDetector.Match] {
        InternationalSensitiveDetector.matches(in:text).filter { $0.type == type }
    }

    func testInternationalPhonesAndUnicodeRanges() {
        let samples = ["+1 (202) 555-0123", "+44 20 7946 0958", "+49 30 12345678", "+33 1 42 68 53 00",
                       "+34 612 345 678", "+351 912 345 678", "+55 11 91234-5678", "+48 512 345 678",
                       "+81 3 1234 5678", "+82 2 1234 5678", "+62 812 3456 7890", "+91 98765 43210",
                       "+61 2 1234 5678", "+7 495 123-45-67", "+971 50 123 4567", "13812345678",
                       "＋８１ ３ １２３４ ５６７８", "+٩٧١ ٥٠ ١٢٣ ٤٥٦٧"]
        for value in samples {
            let text = "📞 Phone: " + value
            let result = matches(text,type:.phoneNumber)
            XCTAssertFalse(result.isEmpty,"Missed synthetic phone: \(value)")
            for match in result { XCTAssertTrue(value.contains((text as NSString).substring(with:match.range))) }
        }
    }

    func testDocumentRulesAndChecksums() {
        let samples = ["SSN: 123-45-6789", "NI number: AB 12 34 56 C", "DNI: 12345678Z",
                       "NIE: X1234567L", "PESEL: 02070803628", "CPF: 529.982.247-25",
                       "NIF: 123456789", "Steuer-ID: 65929970489", "SIN: 046 454 286",
                       "個人番号: 123456789018", "NIK: 3273010101900001", "PAN: ABCPA1234A",
                       "NIR: 180067511234596", "身份证号: 110101199003074518",
                       "Passeport: AB1234567", "護照號碼: X12345678",
                       "L898902C36UTO7408122F1204159ZE184226B<<<<<10"]
        for value in samples { XCTAssertFalse(matches(value,type:.idCard).isEmpty,"Missed synthetic document: \(value)") }
    }

    func testGroupedDocumentFormatsKeepOriginalRanges() {
        let samples = ["PESEL: 02070 803628", "CPF: 529 982 247 25", "NIF: 123 456 789",
                       "NIR: 1 80 06 75 112 345 96", "Steuer-ID: 65 929 970 489",
                       "個人番号: 1234 5678 9018", "個人番号: １２３４ ５６７８ ９０１８",
                       "NIK: 3273 0101 0190 0001", "SSN: 123 45 6789", "SIN: 046-454-286"]
        for value in samples {
            let text = "📄 " + value
            let result = matches(text,type:.idCard)
            XCTAssertEqual(result.count,1,"Grouped document missed: \(value)")
            let range = (text as NSString).range(of:value.components(separatedBy:": ")[1])
            XCTAssertEqual(result.first?.range,range,"Original UTF-16 range must include separators: \(value)")
        }
        for value in ["NIR: 1 80 06 75 112 345 95", "個人番号: 1234 5678 9019", "CPF: 529 982 247 24"] {
            XCTAssertTrue(matches(value,type:.idCard).isEmpty,"Grouped invalid checksum: \(value)")
        }
    }

    func testRejectsBadChecksumsAndOrdinaryIdentifiers() {
        for value in ["DNI: 12345678A", "PESEL: 02070803629", "CPF: 529.982.247-24",
                      "NIF: 123456788", "個人番号: 123456789019", "SSN: 666-12-3456",
                      "NI number: QQ 12 34 56 C", "Passport: JANE", "Order ABC12345678",
                      "Invoice: 1234567890", "2026-10-07", "Serial: 13812345678"] {
            XCTAssertTrue(InternationalSensitiveDetector.matches(in:value).isEmpty,"False candidate: \(value)")
        }
        XCTAssertTrue(matches("123456789012345678901234",type:.phoneNumber).isEmpty)
        XCTAssertTrue(matches("Order: 02070803628",type:.idCard).isEmpty,"PESEL needs a label")
        let mixed = "Phone: +44 20 7946 0958; Invoice: 1234567890"
        XCTAssertEqual(matches(mixed,type:.phoneNumber).count,1)
        let unicodeMRZ = "Straße 📄 L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let mrz = matches(unicodeMRZ,type:.idCard)
        XCTAssertEqual(mrz.count,1)
        XCTAssertEqual(mrz.first?.range,(unicodeMRZ as NSString).range(of:"L898902C36UTO7408122F1204159ZE184226B<<<<<10"))
    }

    func testPhoneExtensionsAndMRZVariants() {
        for value in ["客服电话: 13812345678 转 8001 谢谢配合", "Phone: +44 20 7946 0958 ext. 123"] {
            let result = matches(value,type:.phoneNumber)
            XCTAssertEqual(result.filter { $0.rule == "Apple phone extension" }.count,1)
            XCTAssertTrue(result.contains { (value as NSString).substring(with:$0.range) == "8001" || (value as NSString).substring(with:$0.range) == "123" })
            XCTAssertFalse(result.contains { (value as NSString).substring(with:$0.range).contains(" 转 ") || (value as NSString).substring(with:$0.range).contains("ext.") })
        }
        XCTAssertEqual(matches("L898902C36UTO7408122F1204159ABC123<9",type:.idCard).count,1)
        XCTAssertTrue(matches("L898902C36UTO7408122F1204159ZE184226B<<<<<20",type:.idCard).isEmpty)
    }

    func testRangesAndPageIsolation() {
        let text = "📄 Passeport: AB1234567"
        let target = (text as NSString).range(of:"AB1234567")
        var requested: [NSRange] = []
        let box = CGRect(x:0.2,y:0.5,width:0.3,height:0.1)
        let observations = [0,1].map { page in RecognizedText(text:text,boundingBox:box,confidence:1,pageIndex:page,substringBox: { range in
            requested.append(range);return box
        }) }
        let regions = TextRecognizer.shared.detectSensitiveRegions(in:observations)
        XCTAssertEqual(regions.filter{$0.type == .idCard}.count,2)
        XCTAssertEqual(Set(regions.compactMap(\.pageIndex)),[0,1])
        XCTAssertTrue(requested.contains(target),"Must preserve original UTF-16 coordinates")
    }

    func testRuntimeLanguageConfigurationAndInvalidSavedLanguage() throws {
        let supported = OCRLanguageConfiguration.supportedLanguages()
        XCTAssertFalse(supported.isEmpty)
        let request = VNRecognizeTextRequest()
        try OCRLanguageConfiguration.configure(request,selection:"auto")
        XCTAssertTrue(request.automaticallyDetectsLanguage)
        XCTAssertEqual(Set(request.recognitionLanguages),Set(supported))
        for language in supported {
            try OCRLanguageConfiguration.configure(request,selection:language)
            XCTAssertEqual(request.recognitionLanguages,[language])
            XCTAssertFalse(request.automaticallyDetectsLanguage)
        }
        try OCRLanguageConfiguration.configure(request,selection:"not-an-apple-language")
        XCTAssertTrue(request.automaticallyDetectsLanguage)
        print("INTERNATIONAL_OCR_RUNTIME_LANGUAGES",supported)
    }

    private func renderedImage(_ text: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat();format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:1200,height:400),format:format).image { context in
            UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:1200,height:400))
            (text as NSString).draw(at:CGPoint(x:40,y:150),withAttributes:[.font:UIFont.systemFont(ofSize:40),.foregroundColor:UIColor.black])
        }
    }

    func testAutomaticAndManualOCRSyntheticImages() async throws {
        let key = OCRLanguageConfiguration.preferenceKey
        let saved = UserDefaults.standard.object(forKey:key)
        defer { if let saved { UserDefaults.standard.set(saved,forKey:key) } else { UserDefaults.standard.removeObject(forKey:key) } }
        let samples = [("auto","Téléphone: +33 1 42 68 53 00"),("auto","パスポート: X12345678"),
                       ("auto","護照號碼: X12345678"),("auto","Telefon: +49 30 12345678"),
                       ("ja-JP","パスポート: X12345678")]
        for (selection,value) in samples {
            UserDefaults.standard.set(selection,forKey:key)
            let data = try XCTUnwrap(renderedImage(value).pngData())
            let texts = try await ImageOCRRecognizer().recognizeText(in:data,fileType:.image)
            let regions = TextRecognizer.shared.detectSensitiveRegions(in:texts)
            XCTAssertFalse(regions.isEmpty,"OCR failed \(selection) / \(value): \(texts.map(\.text))")
        }
    }

    func testTextPDFPreservesSpacedInternationalPhoneAndExactBox() async throws {
        let rect = CGRect(x:0,y:0,width:612,height:792)
        let data = UIGraphicsPDFRenderer(bounds:rect).pdfData { renderer in
            renderer.beginPage()
            ("Phone: +44 20 7946 0958" as NSString).draw(at:CGPoint(x:60,y:650),withAttributes:[.font:UIFont.systemFont(ofSize:22)])
        }
        let recognizer = PDFTextRecognizer()
        let texts = try await recognizer.recognizeText(in:data,fileType:.pdf)
        let regions = recognizer.detectSensitiveInfo(in:texts)
        let phone = try XCTUnwrap(regions.first{$0.type == .phoneNumber})
        XCTAssertEqual(phone.pageIndex,0)
        XCTAssertLessThan(phone.boundingBox.midY,220)
        XCTAssertGreaterThan(phone.boundingBox.minX,60)
        XCTAssertTrue(phone.recognizedText?.contains("+44") == true)
    }

    func testScannedPDFOCRAndRotatedPageGeometry() async throws {
        let image = renderedImage("Phone: +44 20 7946 0958")
        let rect = CGRect(x:0,y:0,width:600,height:800)
        let bytes = UIGraphicsPDFRenderer(bounds:rect).pdfData { renderer in
            renderer.beginPage();image.draw(in:CGRect(x:30,y:520,width:540,height:180))
        }
        for rotation in [0,90] {
            let document = try XCTUnwrap(PDFDocument(data:bytes)), page = try XCTUnwrap(document.page(at:0))
            XCTAssertTrue((page.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            page.rotation = rotation
            let data = try XCTUnwrap(document.dataRepresentation())
            let recognizer = PDFTextRecognizer()
            let texts = try await recognizer.recognizeText(in:data,fileType:.pdf)
            let phone = try XCTUnwrap(recognizer.detectSensitiveInfo(in:texts).first{$0.type == .phoneNumber})
            XCTAssertEqual(phone.pageIndex,0)
            XCTAssertGreaterThan(phone.boundingBox.minX,30)
            XCTAssertLessThan(phone.boundingBox.maxY,300)
            XCTAssertTrue(rect.contains(phone.boundingBox),"Invalid page coords at rotation \(rotation)")
        }
    }
}
