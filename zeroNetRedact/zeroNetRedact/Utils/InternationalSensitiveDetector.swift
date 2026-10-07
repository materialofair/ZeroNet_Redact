import Foundation

/// Local candidate detection. A format/check digit is not evidence a document was issued.
enum InternationalSensitiveDetector {
    struct Match {
        let range: NSRange
        let type: SensitiveType
        let rule: String
    }

    private struct DocumentRule {
        let name: String
        let label: String
        let pattern: String
        let validate: (String) -> Bool
    }

    private static let rules: [DocumentRule] = [
        .init(name: "US SSN", label: #"\b(?:SSN|social security)\b"#,
              pattern: #"[0-9]{3}[ -]?[0-9]{2}[ -]?[0-9]{4}"#, validate: validSSN),
        .init(name: "UK NINO", label: #"\b(?:NINO|national insurance|NI number)\b"#,
              pattern: #"[A-Z]{2}[ ]?[0-9]{2}[ ]?[0-9]{2}[ ]?[0-9]{2}[ ]?[A-D]"#, validate: validNINO),
        .init(name: "Spain DNI/NIE", label: #"\b(?:DNI|NIE|NIF)\b"#,
              pattern: #"(?:[0-9]{8}|[XYZ][0-9]{7})[ -]?[A-Z]"#, validate: validSpanishID),
        .init(name: "Poland PESEL", label: #"\bPESEL\b"#,
              pattern: #"[0-9](?:[ -]?[0-9]){10}"#, validate: validPESEL),
        .init(name: "Brazil CPF", label: #"\bCPF\b"#,
              pattern: #"[0-9]{3}[. -]?[0-9]{3}[. -]?[0-9]{3}[- ]?[0-9]{2}"#, validate: validCPF),
        .init(name: "Portugal NIF", label: #"\bNIF\b"#,
              pattern: #"[0-9](?:[ -]?[0-9]){8}"#, validate: validNIF),
        .init(name: "France NIR", label: #"\b(?:NIR|INSEE|sécurité sociale|securite sociale)\b"#,
              pattern: #"[12](?:[ -]?[0-9]){14}"#, validate: validNIR),
        .init(name: "Germany Steuer-ID", label: #"\b(?:Steuer-ID|Steueridentifikationsnummer|IdNr)\b"#,
              pattern: #"[1-9](?:[ -]?[0-9]){10}"#, validate: validGermanTaxID),
        .init(name: "Canada SIN", label: #"\b(?:SIN|NAS|social insurance)\b"#,
              pattern: #"[0-9]{3}[ -]?[0-9]{3}[ -]?[0-9]{3}"#, validate: validSIN),
        .init(name: "Japan My Number", label: #"マイナンバー|個人番号|\bMy Number\b"#,
              pattern: #"[0-9](?:[ -]?[0-9]){11}"#, validate: validMyNumber),
        .init(name: "Indonesia NIK", label: #"\b(?:NIK|nomor induk kependudukan)\b"#,
              pattern: #"[0-9](?:[ -]?[0-9]){15}"#, validate: validNIK),
        .init(name: "India PAN", label: #"\b(?:PAN|permanent account number)\b"#,
              pattern: #"[A-Z]{3}[ABCFGHJLPT][A-Z][0-9]{4}[A-Z]"#, validate: { _ in true }),
    ]

    static func matches(in text: String, nearbyLabel: String = "") -> [Match] {
        // One UTF-16 unit maps to one unit: full-width/Arabic digits retain exact OCR geometry.
        let normalized = normalizedText(text)
        let ns = normalized as NSString
        let context = nearbyLabel + "\n" + normalized
        var found: [Match] = []
        func add(_ range: NSRange, _ type: SensitiveType, _ rule: String) {
            guard range.length > 0, !found.contains(where: { $0.type == type && $0.range == range }) else { return }
            found.append(.init(range: range, type: type, rule: rule))
        }

        // Retain Chinese legacy format candidates; OCR errors may invalidate the check digit.
        for result in regex(#"(?<![A-Za-z0-9])[1-9][0-9]{5}[ ]?(?:[12][0-9]{3}|[0-9]{2})[ ]?(?:0[1-9]|1[0-2])[ ]?(?:0[1-9]|[12][0-9]|3[01])[ ]?[0-9]{3}[0-9Xx]?(?![A-Za-z0-9])"#, in: normalized) {
            let value = compact(ns.substring(with: result.range))
            if value.count == 15 || value.count == 18 { add(result.range, .idCard, "China legacy ID format") }
        }
        for rule in rules where hasLabel(rule.label, in: context) {
            for result in regex("(?<![A-Za-z0-9])(?:" + rule.pattern + ")(?![A-Za-z0-9])", in: normalized) {
                if rule.validate(compact(ns.substring(with: result.range)).uppercased()) {
                    add(result.range, .idCard, rule.name)
                }
            }
        }

        // ICAO TD3 passport and TD2 document second lines: verify document, DOB and expiry check digits.
        for result in regex(#"(?<![A-Z0-9<])(?:[A-Z0-9<]{9}[0-9][A-Z<]{3}[0-9]{6}[0-9][MF<][0-9]{6}[0-9][A-Z0-9<]{14}[0-9<][0-9]|[A-Z0-9<]{9}[0-9][A-Z<]{3}[0-9]{6}[0-9][MF<][0-9]{6}[0-9][A-Z0-9<]{7}[0-9])(?![A-Z0-9<])"#, in: normalized) {
            if validMRZ(ns.substring(with: result.range).uppercased()) { add(result.range, .idCard, "ICAO TD3/TD2 MRZ") }
        }

        let passportLabel = #"passport|passeport|reisepass|pasaporte|passaporte|paszport|paspor|passaporto|パスポート|여권|паспорт|جواز السفر|hộ chiếu|護照|护照"#
        let genericLabel = #"ID number|identity number|identification number|document number|national ID|Ausweisnummer|Personalausweisnummer|numéro de carte|numero de carte|身分證字號|身份证号码|證件號碼|证件号码|رقم الهوية"#
        let label = "(?:" + passportLabel + "|" + genericLabel + ")"
        let labelledPattern = label + #"\s*(?:(?:no\.?|number|nr\.?|nummer|numéro|número|nomor|番号|号码|號碼)\s*)?[:#：]?\s*([A-Z0-9]{5,18})(?![A-Z0-9])"#
        for result in regex(labelledPattern, in: normalized) {
            let range = result.range(at: 1)
            let value = ns.substring(with: range)
            if containsDigit(value) { add(range, .idCard, "Labelled document number (format only)") }
        }
        // Labels on the immediately adjacent line, never an arbitrary whole-page keyword.
        if hasLabel(label, in: nearbyLabel), let result = regex(#"^\s*([A-Z0-9]{5,18})\s*$"#, in: normalized).first {
            let range = result.range(at: 1)
            if containsDigit(ns.substring(with: range)) { add(range, .idCard, "Adjacent document label (format only)") }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            for result in detector.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
                let fullValue = ns.substring(with: result.range)
                // Apple's detector may include an extension. Keep separate tight boxes, validating the base only.
                let extensionMatch = regex(#"(?:ext\.?|extension|x|#|转|轉|内線)\s*[:.]?\s*([0-9]{1,8})\s*$"#, in:fullValue).last
                let base = extensionMatch.map { (fullValue as NSString).substring(to:$0.range.location).trimmingCharacters(in:.whitespaces) } ?? fullValue
                let baseRange = NSRange(location:result.range.location,length:(base as NSString).length)
                if validPhoneCandidate(base), phoneContextAllowed(baseRange, in: ns), !found.contains(where: { $0.type == .idCard && NSIntersectionRange($0.range, result.range).length > 0 }),
                   asciiTokenBoundary(result.range, in: ns) {
                    add(baseRange, .phoneNumber, "Apple phone detector")
                    if let extensionMatch {
                        let digits = extensionMatch.range(at:1)
                        add(NSRange(location:result.range.location+digits.location,length:digits.length), .phoneNumber, "Apple phone extension")
                    }
                }
            }
        }
        // Preserve unformatted Chinese mobile support if the device's detector locale misses it.
        for result in regex(#"(?<![A-Za-z0-9])1[3-9][0-9][ -]?[0-9]{4}[ -]?[0-9]{4}(?![A-Za-z0-9])"#, in: normalized) {
            if phoneContextAllowed(result.range, in: ns), !found.contains(where: { $0.type == .idCard && NSIntersectionRange($0.range, result.range).length > 0 }) {
                add(result.range, .phoneNumber, "China mobile")
            }
        }
        return found.sorted { $0.type == .idCard && $1.type != .idCard }
    }

    private static func normalizedText(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            if scalar.value <= 0xFFFF, let number = scalar.properties.numericValue, (0...9).contains(number), number.rounded() == number,
               scalar.properties.numericType == .decimal { return Character(String(Int(number))) }
            switch scalar.value {
            case 0xFF0B: return "+"
            case 0xFF0D, 0x2010, 0x2011, 0x2013: return "-"
            case 0xFF08: return "("
            case 0xFF09: return ")"
            case 0x00A0, 0x202F: return " "
            default: return Character(scalar)
            }
        })
    }

    private static func regex(_ pattern: String, in value: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .matches(in: value, range: NSRange(value.startIndex..., in: value)) ?? []
    }
    private static func hasLabel(_ pattern: String, in value: String) -> Bool { !regex(pattern, in: value).isEmpty }
    private static func compact(_ value: String) -> String { value.filter { $0.isLetter || $0.isNumber } }
    private static func containsDigit(_ value: String) -> Bool { value.contains { $0.isNumber } }
    private static func digits(_ value: String) -> [Int] { value.compactMap(\.wholeNumberValue) }
    private static func asciiTokenBoundary(_ range: NSRange, in text: NSString) -> Bool {
        func token(_ unit: unichar) -> Bool { (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit) }
        return (range.location == 0 || !token(text.character(at: range.location - 1)))
            && (NSMaxRange(range) == text.length || !token(text.character(at: NSMaxRange(range))))
    }
    private static func validPhoneCandidate(_ value: String) -> Bool {
        let d = digits(value)
        return regex(#"[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}"#, in: value).isEmpty
            && (7...15).contains(d.count) && Set(d).count > 1
            && (!value.trimmingCharacters(in: .whitespaces).hasPrefix("+") || d.first != 0)
    }
    private static func phoneContextAllowed(_ range: NSRange, in text: NSString) -> Bool {
        let start = max(0, range.location - 48)
        let prefix = text.substring(with: NSRange(location:start,length:range.location-start))
        let phoneLabels = regex(#"\b(?:phone|tel|telephone|mobile|call|fax)\b|电话|電話|☎"#, in:prefix)
        let labels = #"\b(?:order|invoice|reference|tracking|serial|SKU|IBAN|account|SSN|CPF|NIF|DNI|NIE|PESEL|NIR|INSEE|SIN|NAS|NIK|PAN|NINO|Steuer-ID|IdNr|social security|social insurance|national insurance|permanent account number)\b|订单|訂單|发票|發票|卡号|卡號|個人番号|マイナンバー|sécurité sociale|securite sociale"#
        let otherLabels = regex(labels, in:prefix)
        guard let other = otherLabels.last else { return true }
        return (phoneLabels.last?.range.location ?? -1) > other.range.location
    }
    private static func validSSN(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 9 else { return false }
        let area = d[0] * 100 + d[1] * 10 + d[2]
        return area > 0 && area != 666 && area < 900 && d[3...4].contains(where: { $0 != 0 }) && d[5...8].contains(where: { $0 != 0 })
    }
    private static func validNINO(_ value: String) -> Bool {
        let a = Array(value); guard a.count == 9 else { return false }
        return !"DFIQUV".contains(a[0]) && !"DFIQUVO".contains(a[1]) && !["BG","GB","KN","NK","NT","TN","ZZ"].contains(String(a.prefix(2)))
    }
    private static func validSpanishID(_ value: String) -> Bool {
        let a = Array(value); guard a.count == 9 else { return false }
        var number = String(a.prefix(8))
        if let first = a.first, let replacement = ["X":"0","Y":"1","Z":"2"][String(first)] { number = replacement + String(a[1..<8]) }
        guard let n = Int(number) else { return false }
        return Array("TRWAGMYFPDXBNJZSQVHLCKE")[n % 23] == a[8]
    }
    private static func validPESEL(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 11 else { return false }
        let month = d[2]*10+d[3], century = [0:1900,1:2000,2:2100,3:2200,4:1800][month / 20]
        guard let century, validDate(year: century+d[0]*10+d[1], month: month%20, day: d[4]*10+d[5]) else { return false }
        let weights = [1,3,7,9,1,3,7,9,1,3]
        return (10 - zip(d.prefix(10),weights).map(*).reduce(0,+)%10)%10 == d[10]
    }
    private static func validCPF(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 11, Set(d).count > 1 else { return false }
        for n in [9,10] {
            let sum = (0..<n).reduce(0) { $0+d[$1]*(n+1-$1) }
            if ((sum*10)%11)%10 != d[n] { return false }
        }
        return true
    }
    private static func validNIF(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 9, [1,2,3,5,6,7,8,9].contains(d[0]) else { return false }
        let r = 11-(0..<8).reduce(0) { $0+d[$1]*(9-$1) }%11
        return (r >= 10 ? 0 : r) == d[8]
    }
    private static func validNIR(_ value: String) -> Bool {
        guard value.count == 15, let base = Int(value.prefix(13)), let check = Int(value.suffix(2)) else { return false }
        return 97-base%97 == check
    }
    private static func validGermanTaxID(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 11, d[0] != 0 else { return false }
        var product = 10
        for digit in d.prefix(10) { let sum = (digit+product)%10; product = ((sum == 0 ? 10 : sum)*2)%11 }
        return (11-product)%10 == d[10]
    }
    private static func validSIN(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 9, Set(d).count > 1 else { return false }
        return d.enumerated().reduce(0) { result, pair in let n = pair.element*(pair.offset%2 == 1 ? 2 : 1); return result+n/10+n%10 }%10 == 0
    }
    private static func validMyNumber(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 12, Set(d).count > 1 else { return false }
        let sum = d.prefix(11).reversed().enumerated().reduce(0) { $0+$1.element*($1.offset%6+2) }
        let r = sum%11
        return (r <= 1 ? 0 : 11-r) == d[11]
    }
    private static func validNIK(_ value: String) -> Bool {
        let d = digits(value); guard d.count == 16, d[0] != 0 else { return false }
        let day = d[6]*10+d[7], month = d[8]*10+d[9], year = d[10]*10+d[11]
        return validDate(year:1900+year,month:month,day:day>40 ? day-40 : day)
            || validDate(year:2000+year,month:month,day:day>40 ? day-40 : day)
    }
    private static func validDate(year: Int, month: Int, day: Int) -> Bool {
        let calendar = Calendar(identifier:.gregorian)
        guard let date = calendar.date(from:DateComponents(year:year,month:month,day:day)) else { return false }
        let actual = calendar.dateComponents([.year,.month,.day],from:date)
        return actual.year == year && actual.month == month && actual.day == day
    }
    private static func mrzDigit(_ value: String) -> Int? {
        var sum = 0
        for (i,c) in value.utf8.enumerated() {
            let number: Int
            if c == 60 { number = 0 } else if (48...57).contains(c) { number = Int(c-48) }
            else if (65...90).contains(c) { number = Int(c-65)+10 } else { return nil }
            sum += number * [7,3,1][i%3]
        }
        return sum%10
    }
    private static func validMRZ(_ value: String) -> Bool {
        let a = Array(value); guard a.count == 44 || a.count == 36 else { return false }
        for (range,index) in [(0..<9,9),(13..<19,19),(21..<27,27)] {
            if mrzDigit(String(a[range])) != a[index].wholeNumberValue { return false }
        }
        for range in [13..<19, 21..<27] {
            let value = String(a[range])
            let d = digits(value)
            guard d.count == 6, validDate(year:2000+d[0]*10+d[1],month:d[2]*10+d[3],day:d[4]*10+d[5]) else { return false }
        }
        if a.count == 44 {
            let optional = String(a[28..<42])
            let expected = mrzDigit(optional)
            guard expected == a[42].wholeNumberValue || (optional.allSatisfy { $0 == "<" } && a[42] == "<") else { return false }
        }
        let composite = String(a[0..<10])+String(a[13..<20])+String(a[21..<28])+String(a[28..<(a.count-1)])
        return mrzDigit(composite) == a.last?.wholeNumberValue
    }
}
