import Foundation

struct RegexPatterns {

    // Top ~200 common Chinese surnames
    static let surnames: Set<String> = [
        "王","李","张","刘","陈","杨","黄","赵","周","吴",
        "徐","孙","马","胡","朱","郭","何","罗","高","林",
        "郑","梁","谢","唐","许","韩","冯","邓","曹","彭",
        "曾","萧","田","董","潘","袁","于","蒋","蔡","余",
        "杜","叶","程","苏","魏","吕","丁","任","沈","姚",
        "卢","姜","崔","钟","谭","陆","汪","范","金","石",
        "廖","贾","夏","韦","付","方","白","邹","孟","熊",
        "秦","邱","江","尹","薛","闫","段","雷","侯","龙",
        "史","陶","黎","贺","顾","毛","郝","龚","邵","万",
        "钱","严","覃","武","戴","莫","孔","向","汤","温",
        "康","常","阮","倪","童","柳","鲍","屈","庞","蓝",
        "聂","齐","鲁","辛","庄","殷","章","詹","祁","管",
        "祝","左","涂","谷","祁","时","舒","耿","牟","卜",
        "路","关","岳","樊","凌","纪","柯","焦","池","甘",
        "查","牛","敖","单","包","司","申","冉","游","兰",
        "宁","芦","季","成","盛","乔","裴","房","代","迟",
    ]

    static func pattern(for type: SensitiveType) -> String {
        switch type {
        case .phone:
            return #"1[3-9]\d{9}"#
        case .idCard:
            return #"\b\d{17}[\dXx]\b|\b\d{15}\b"#
        case .email:
            return #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#
        case .bankCard:
            return #"\b\d{16,19}\b"#
        case .chineseName:
            // Free text only treats slash-separated personnel lists as names.
            // A bare surname-like substring inside prose is too ambiguous.
            let surnameGroup = surnames.sorted().joined(separator: "|")
            let single = "(?:\(surnameGroup))[\\u4E00-\\u9FFF]{1,2}"
            return "(?<![\\u4E00-\\u9FFF])\(single)(?:\\s*/\\s*\(single))+(?![\\u4E00-\\u9FFF])"
        case .companyName:
            // High-confidence legal entity names. Short brands without a legal
            // suffix are detected through explicit table headers instead.
            return #"(?<![\p{Han}A-Za-z0-9])[\p{Han}A-Za-z0-9（）()·&]{2,40}?(?:股份有限公司|有限责任公司|有限公司)(?![\p{Han}A-Za-z0-9])"#
        case .address:
            // Match full Chinese address strings, non-greedy between key components
            return #"[一-鿿]{2,}(?:省|市|区|县)[一-鿿0-9]{0,30}?(?:街道|路|街|大道|道|巷|弄)[一-鿿0-9]{0,20}?(?:号|号楼|楼|栋|幢|层|单元|室|厦|园|城|工业园)"#
        case .landline:
            return #"\b0\d{2,3}[-]?\d{7,8}\b"#
        }
    }

    static func detectSensitiveTypes(in value: String) -> [SensitiveType] {
        var detected: [SensitiveType] = []

        // Check Chinese name via surname matching (not regex)
        if isChineseName(value) {
            detected.append(.chineseName)
        }

        // Regex-based checks
        for type in SensitiveType.allCases where type != .chineseName && type != .address {
            let pat = pattern(for: type)
            guard !pat.isEmpty,
                  let regex = try? NSRegularExpression(pattern: pat) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if regex.firstMatch(in: value, range: range) != nil {
                detected.append(type)
            }
        }

        // Disambiguation: if idCard matched, remove phone/bankCard (18-digit IDs are not phones)
        if detected.contains(.idCard) {
            detected.removeAll { $0 == .phone || $0 == .bankCard }
        }

        return detected
    }

    static func detectSensitiveTypes(in values: [String]) -> [SensitiveType] {
        let nonEmpty = values.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return [] }

        var typeHits: [SensitiveType: Int] = [:]
        for value in nonEmpty {
            for type in detectSensitiveTypes(in: value) {
                typeHits[type, default: 0] += 1
            }
        }

        // chineseName requires higher threshold (>= 50%) to reduce false positives
        let nameThreshold = max(2, nonEmpty.count / 2)
        let defaultThreshold = max(1, nonEmpty.count / 3)

        return typeHits.compactMap { type, hits in
            let threshold = (type == .chineseName) ? nameThreshold : defaultThreshold
            return hits >= threshold ? type : nil
        }
    }

    // MARK: - Chinese name detection

    static func isChineseName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Split by common separators: / \n 空格
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "/\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return false }

        // Each part must be a valid 2-3 char Chinese name starting with a surname.
        // The current surname set contains single-character surnames only.
        return parts.allSatisfy { part in
            guard part.count >= 2 && part.count <= 3 else { return false }
            guard part.allSatisfy({ char in
                guard let scalar = char.unicodeScalars.first else { return false }
                return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
            }) else { return false }
            return surnames.contains(String(part.first!))
        }
    }
}
