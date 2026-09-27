import Foundation

private struct TestFailure: Error {
    let message: String
}

private var passed = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(message: message) }
    passed += 1
    print("✓ \(message)")
}

do {
    try expect(
        RegexPatterns.detectSensitiveTypes(in: "13812345678").contains(.phone),
        "识别中国大陆手机号"
    )

    let idTypes = RegexPatterns.detectSensitiveTypes(in: "110101199003071234")
    try expect(
        idTypes.contains(.idCard) && !idTypes.contains(.phone) && !idTypes.contains(.bankCard),
        "身份证号不被误判为手机号或银行卡"
    )

    try expect(
        RegexPatterns.isChineseName("张三/李四") && !RegexPatterns.isChineseName("数据中台"),
        "支持多姓名并过滤非姓名中文词"
    )

    try expect(
        RegexPatterns.detectSensitiveTypes(in: "杭州博日科技股份有限公司")
            .contains(.companyName),
        "识别带法定后缀的供应商名称"
    )

    try expect(
        !RegexPatterns.detectSensitiveTypes(in: "于是委托生产并跟进改善")
            .contains(.chineseName),
        "普通正文短语不被误判为姓名"
    )

    try expect(
        !RegexPatterns.detectSensitiveTypes(in: "广东省深圳市宝安区福海街道远东东路2号")
            .contains(.address),
        "地址不进入脱敏类型"
    )

    let columnTypes = RegexPatterns.detectSensitiveTypes(in: [
        "zhangsan@example.com", "lisi@example.com", "无", "wang@example.com"
    ])
    try expect(columnTypes.contains(.email), "按样本命中率识别邮箱列")

    let originalURL = URL(fileURLWithPath: "/tmp/客户清单.xlsx")
    try expect(
        FileFormatUtils.desensitizedFileName(for: originalURL) == "客户清单_脱敏.xlsx",
        "生成脱敏文件名"
    )
    try expect(
        FileFormatUtils.mappingFileName(for: originalURL) == "客户清单_脱敏映射表.xlsx",
        "映射表使用 XLSX 命名规则"
    )
    try expect(
        FileFormatUtils.recoveredFileName(for: URL(fileURLWithPath: "/tmp/客户清单_脱敏.xlsx"))
            == "客户清单_脱敏恢复版.xlsx",
        "恢复文件名不重复追加脱敏后缀"
    )
    try expect(
        FileFormatUtils.isWithinFileSizeLimit(100 * 1024 * 1024),
        "100MB 边界文件允许处理"
    )
    try expect(
        !FileFormatUtils.isWithinFileSizeLimit(100 * 1024 * 1024 + 1),
        "超过 100MB 的文件被拒绝"
    )
    try expect(
        FileFormatUtils.isLegacyOfficeFormat(url: URL(fileURLWithPath: "/tmp/旧表格.xls"))
            && FileFormatUtils.modernExtension(
                forLegacyURL: URL(fileURLWithPath: "/tmp/旧表格.xls")
            ) == "xlsx",
        "旧版 Excel 提示转换为 XLSX"
    )
    try expect(
        FileFormatUtils.supportedExtensions() == ["xlsx"]
            && FileFormatUtils.isSupported(url: URL(fileURLWithPath: "/tmp/客户清单.xlsx"))
            && !FileFormatUtils.isSupported(url: URL(fileURLWithPath: "/tmp/文档.docx"))
            && !FileFormatUtils.isSupported(url: URL(fileURLWithPath: "/tmp/演示.pptx")),
        "当前仅支持 XLSX，Word 和 PPT 均不开放"
    )

    print("\n核心逻辑测试通过：\(passed) 项")
} catch let failure as TestFailure {
    fputs("✗ \(failure.message)\n", stderr)
    exit(1)
} catch {
    fputs("✗ \(error.localizedDescription)\n", stderr)
    exit(1)
}
