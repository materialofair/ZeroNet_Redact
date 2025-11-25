# 🏗️ ZeroNet Redact 技术架构设计

**版本**：V3.0 - 可扩展多文件类型架构  
**最后更新**：2025-01-19

---

## 目录

1. [架构总览](#架构总览)
2. [可扩展性设计原则](#可扩展性设计原则)
3. [模块设计](#模块设计)
4. [数据模型](#数据模型)
5. [文件类型抽象层](#文件类型抽象层)
6. [加密系统](#加密系统)
7. [智能识别引擎](#智能识别引擎)
8. [编辑引擎](#编辑引擎)
9. [存储架构](#存储架构)
10. [性能优化](#性能优化)
11. [安全设计](#安全设计)
12. [PDF扩展实现](#pdf扩展实现)

---

## 架构总览

### 系统分层架构（可扩展版）

```
┌──────────────────────────────────────────────────────────┐
│                  UI Layer (SwiftUI)                      │
│  ┌────────────┬─────────────────┬──────────────────┐    │
│  │ 导入界面    │  编辑器容器界面  │   相册界面        │    │
│  │            │  ├─图片编辑器    │   ├─原相册        │    │
│  │            │  └─PDF编辑器     │   └─脱敏相册      │    │
│  └────────────┴─────────────────┴──────────────────┘    │
├──────────────────────────────────────────────────────────┤
│              Business Logic Layer (Swift)                │
│  ┌────────────┬──────────────────┬──────────────────┐   │
│  │ImportMgr   │ EditorFactory    │  AlbumManager    │   │
│  │  ├─Image   │  ├─ImageEditor   │   ├─Originals    │   │
│  │  └─PDF     │  └─PDFEditor     │   └─Redacted     │   │
│  ├────────────┼──────────────────┼──────────────────┤   │
│  │TextRecognizer│  CryptoEngine  │ StorageManager   │   │
│  │  ├─OCR(图片)│                 │   ├─Image Store  │   │
│  │  └─PDF文字  │                 │   └─PDF Store    │   │
│  └────────────┴──────────────────┴──────────────────┘   │
├──────────────────────────────────────────────────────────┤
│          Protocol Layer (抽象层) 🆕                      │
│  ┌──────────────────────────────────────────────────┐   │
│  │ RedactableFile Protocol (文件类型抽象)             │   │
│  │ RedactionEditor Protocol (编辑器抽象)              │   │
│  │ TextRecognition Protocol (文字识别抽象)            │   │
│  └──────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────┤
│              Data Layer (Core Data)                      │
│  ┌────────────┬────────────┬───────────────────────┐    │
│  │OriginalFile│RedactedFile│  SensitiveRegion      │    │
│  │ (多态支持)  │ (多态支持)  │                       │    │
│  └────────────┴────────────┴───────────────────────┘    │
├──────────────────────────────────────────────────────────┤
│              iOS Framework Layer                         │
│  ┌────────────┬────────────┬──────────┬──────────────┐  │
│  │   Vision   │  CryptoKit │CoreImage │   PDFKit 🆕  │  │
│  ├────────────┼────────────┼──────────┼──────────────┤  │
│  │  CoreML    │  Keychain  │  Photos  │   QuickLook  │  │
│  └────────────┴────────────┴──────────┴──────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 可扩展性设计原则

### 🎯 核心设计原则

1. **开闭原则（Open-Closed Principle）**  
   对扩展开放，对修改关闭。添加PDF支持不修改现有图片代码。

2. **依赖倒置原则（Dependency Inversion）**  
   高层模块（UI）依赖抽象（Protocol），不依赖具体实现。

3. **单一职责原则（Single Responsibility）**  
   每个模块只负责一种文件类型的处理逻辑。

4. **策略模式（Strategy Pattern）**  
   编辑器、识别器、存储器都可以根据文件类型动态切换。

### 🔧 扩展路径设计

```
V1.0 (图片脱敏)
    ↓
添加 Protocol 抽象层
    ↓
V1.5 (PDF脱敏) ← 只需实现 Protocol，0修改现有代码
    ↓
V2.0 (视频脱敏) ← 同样模式扩展
    ↓
V3.0 (Word/Excel) ← 继续扩展
```

---

## 文件类型抽象层 🆕

### 核心协议定义

```swift
// MARK: - 文件类型枚举
enum FileType: String, Codable {
    case image  // 图片（PNG/JPEG）
    case pdf    // PDF文档
    // 未来扩展：
    // case video
    // case document
    
    var displayName: String {
        switch self {
        case .image: return "图片"
        case .pdf: return "PDF文档"
        }
    }
    
    var supportedExtensions: [String] {
        switch self {
        case .image: return ["png", "jpg", "jpeg", "heic"]
        case .pdf: return ["pdf"]
        }
    }
}

// MARK: - 可脱敏文件协议
protocol RedactableFile {
    var id: UUID { get }
    var fileType: FileType { get }
    var encryptedDataPath: String { get }
    var createdAt: Date { get }
    var fileSize: Int64 { get }
    
    // 类型特定属性
    var typeSpecificMetadata: [String: Any] { get }
}

// MARK: - 脱敏编辑器协议
protocol RedactionEditor: AnyObject {
    associatedtype FileType: RedactableFile
    
    // 加载文件
    func loadFile(_ file: FileType) async throws
    
    // 智能识别敏感区域
    func detectSensitiveRegions() async throws -> [SensitiveRegion]
    
    // 应用脱敏
    func applyRedaction(at region: CGRect, effect: RedactionEffect)
    
    // 撤销/重做
    func undo()
    func redo()
    
    // 导出脱敏文件
    func exportRedactedFile() async throws -> Data
}

// MARK: - 文字识别协议
protocol TextRecognition {
    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText]
    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion]
}

// MARK: - 脱敏效果枚举
enum RedactionEffect {
    case mosaic(pixelSize: Int)
    case blur(radius: Float)
    case rectangle(color: UIColor, opacity: Float)
    case solidBlack
}

// MARK: - 识别的文字结构
struct RecognizedText {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let pageIndex: Int?  // PDF多页支持
}
```

---

## 模块设计

### 1. ImportManager（导入管理器）- 支持多文件类型

```swift
class ImportManager {
    static let shared = ImportManager()
    
    // MARK: - 统一导入接口
    func importFiles(from sources: [ImportSource]) async throws -> [RedactableFile] {
        var files: [RedactableFile] = []
        
        for source in sources {
            let file = try await processImport(source)
            files.append(file)
        }
        
        return files
    }
    
    // MARK: - 导入源枚举
    enum ImportSource {
        case photo(PHAsset)
        case fileURL(URL)
        case dropItem(NSItemProvider)
    }
    
    // MARK: - 内部处理逻辑
    private func processImport(_ source: ImportSource) async throws -> RedactableFile {
        // 1. 检测文件类型
        let fileType = detectFileType(from: source)
        
        // 2. 根据类型选择处理器
        let processor: FileImportProcessor
        switch fileType {
        case .image:
            processor = ImageImportProcessor()
        case .pdf:
            processor = PDFImportProcessor()
        }
        
        // 3. 处理导入
        let data = try await processor.loadData(from: source)
        
        // 4. 加密存储
        let encryptedData = try CryptoEngine.shared.encrypt(data: data)
        
        // 5. 创建文件记录
        return try await createFileRecord(
            data: encryptedData,
            type: fileType,
            processor: processor
        )
    }
    
    // MARK: - 文件类型检测
    private func detectFileType(from source: ImportSource) -> FileType {
        switch source {
        case .photo:
            return .image
        case .fileURL(let url):
            let ext = url.pathExtension.lowercased()
            if ["pdf"].contains(ext) {
                return .pdf
            } else {
                return .image
            }
        case .dropItem(let item):
            // 根据UTType判断
            if item.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                return .pdf
            } else {
                return .image
            }
        }
    }
}

// MARK: - 文件导入处理器协议
protocol FileImportProcessor {
    func loadData(from source: ImportManager.ImportSource) async throws -> Data
    func generateThumbnail(from data: Data) async throws -> Data
    func extractMetadata(from data: Data) -> [String: Any]
}

// MARK: - 图片导入处理器
class ImageImportProcessor: FileImportProcessor {
    func loadData(from source: ImportManager.ImportSource) async throws -> Data {
        // 现有图片导入逻辑
        // ...
    }
    
    func generateThumbnail(from data: Data) async throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImportError.invalidImageData
        }
        
        let size = CGSize(width: 200, height: 200)
        let thumbnail = image.thumbnailImage(size: size)
        return thumbnail.pngData() ?? Data()
    }
    
    func extractMetadata(from data: Data) -> [String: Any] {
        guard let image = UIImage(data: data) else { return [:] }
        
        return [
            "width": image.size.width,
            "height": image.size.height,
            "orientation": image.imageOrientation.rawValue
        ]
    }
}

// MARK: - PDF导入处理器 🆕
class PDFImportProcessor: FileImportProcessor {
    func loadData(from source: ImportManager.ImportSource) async throws -> Data {
        switch source {
        case .fileURL(let url):
            return try Data(contentsOf: url)
        case .dropItem(let item):
            return try await withCheckedThrowingContinuation { continuation in
                item.loadDataRepresentation(forTypeIdentifier: "com.adobe.pdf") { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    }
                }
            }
        default:
            throw ImportError.unsupportedSource
        }
    }
    
    func generateThumbnail(from data: Data) async throws -> Data {
        guard let document = PDFDocument(data: data),
              let firstPage = document.page(at: 0) else {
            throw ImportError.invalidPDFData
        }
        
        let pageRect = firstPage.bounds(for: .mediaBox)
        let thumbnail = firstPage.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
        
        return thumbnail.pngData() ?? Data()
    }
    
    func extractMetadata(from data: Data) -> [String: Any] {
        guard let document = PDFDocument(data: data) else { return [:] }
        
        return [
            "pageCount": document.pageCount,
            "title": document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "",
            "author": document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        ]
    }
}
```

---

### 2. EditorFactory（编辑器工厂）🆕

```swift
class EditorFactory {
    // MARK: - 创建编辑器
    static func createEditor(for file: RedactableFile) -> any RedactionEditor {
        switch file.fileType {
        case .image:
            return ImageRedactionEditor(file: file as! OriginalImage)
        case .pdf:
            return PDFRedactionEditor(file: file as! OriginalPDF)
        }
    }
}
```

---

### 3. TextRecognizer（统一文字识别器）🆕

```swift
class TextRecognizer {
    static let shared = TextRecognizer()
    
    // MARK: - 统一识别接口
    func recognizeText(in file: RedactableFile) async throws -> [RecognizedText] {
        let recognizer: TextRecognition
        
        switch file.fileType {
        case .image:
            recognizer = ImageOCRRecognizer()
        case .pdf:
            recognizer = PDFTextRecognizer()
        }
        
        // 加载解密数据
        let data = try await loadDecryptedData(for: file)
        
        // 执行识别
        return try await recognizer.recognizeText(in: data, fileType: file.fileType)
    }
    
    // MARK: - 检测敏感信息
    func detectSensitiveRegions(in texts: [RecognizedText]) -> [SensitiveRegion] {
        var regions: [SensitiveRegion] = []
        
        for text in texts {
            // 手机号
            if let phoneRegions = matchPattern(SensitivePatterns.phoneNumber, in: text) {
                regions.append(contentsOf: phoneRegions)
            }
            
            // 邮箱
            if let emailRegions = matchPattern(SensitivePatterns.email, in: text) {
                regions.append(contentsOf: emailRegions)
            }
            
            // 身份证
            if let idRegions = matchPattern(SensitivePatterns.idCard, in: text) {
                regions.append(contentsOf: idRegions)
            }
            
            // 银行卡
            if let bankRegions = matchPattern(SensitivePatterns.bankCard, in: text) {
                regions.append(contentsOf: bankRegions)
            }
        }
        
        return regions
    }
    
    private func matchPattern(_ pattern: String, in text: RecognizedText) -> [SensitiveRegion]? {
        // 正则匹配实现
        // ...
    }
}

// MARK: - 图片OCR识别器（现有）
class ImageOCRRecognizer: TextRecognition {
    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        guard let image = UIImage(data: data) else {
            throw RecognitionError.invalidImageData
        }
        
        // 使用Vision API识别
        // ... 现有实现
    }
    
    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion] {
        // 委托给TextRecognizer.shared
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
}

// MARK: - PDF文字识别器 🆕
class PDFTextRecognizer: TextRecognition {
    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        guard let document = PDFDocument(data: data) else {
            throw RecognitionError.invalidPDFData
        }
        
        var allTexts: [RecognizedText] = []
        
        // 遍历所有页面
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // PDF可以直接获取文字和位置（不需要OCR！）
            if let pageContent = page.string {
                // 使用PDFSelection获取每个单词的位置
                let selections = page.findString(pageContent, withOptions: .caseInsensitive)
                
                for selection in selections {
                    let bounds = selection.bounds(for: page)
                    
                    allTexts.append(RecognizedText(
                        text: selection.string ?? "",
                        boundingBox: bounds,
                        confidence: 1.0,  // PDF文字是100%准确的
                        pageIndex: pageIndex
                    ))
                }
            }
        }
        
        return allTexts
    }
    
    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion] {
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
}
```

---

## 数据模型

### Core Data Schema（多态支持）

```swift
// MARK: - 基础文件实体（抽象父类）
@objc(OriginalFile)
public class OriginalFile: NSManagedObject, RedactableFile {
    @NSManaged public var id: UUID
    @NSManaged public var fileTypeRaw: String  // FileType.rawValue
    @NSManaged public var encryptedDataPath: String
    @NSManaged public var encryptedThumbnailPath: String
    @NSManaged public var createdAt: Date
    @NSManaged public var fileSize: Int64
    
    // 类型特定元数据（JSON存储）
    @NSManaged public var metadataJSON: String?
    
    // 关系：一对多
    @NSManaged public var redactedVersions: NSSet?
    
    // MARK: - 计算属性
    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .image }
        set { fileTypeRaw = newValue.rawValue }
    }
    
    var typeSpecificMetadata: [String: Any] {
        guard let json = metadataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

// MARK: - 图片文件（子类）
@objc(OriginalImage)
public class OriginalImage: OriginalFile {
    // 图片特定属性
    var width: Int32 {
        get { typeSpecificMetadata["width"] as? Int32 ?? 0 }
    }
    
    var height: Int32 {
        get { typeSpecificMetadata["height"] as? Int32 ?? 0 }
    }
    
    var orientation: UIImage.Orientation {
        let rawValue = typeSpecificMetadata["orientation"] as? Int ?? 0
        return UIImage.Orientation(rawValue: rawValue) ?? .up
    }
}

// MARK: - PDF文件（子类）🆕
@objc(OriginalPDF)
public class OriginalPDF: OriginalFile {
    // PDF特定属性
    var pageCount: Int {
        get { typeSpecificMetadata["pageCount"] as? Int ?? 0 }
    }
    
    var title: String {
        get { typeSpecificMetadata["title"] as? String ?? "" }
    }
    
    var author: String {
        get { typeSpecificMetadata["author"] as? String ?? "" }
    }
}

// MARK: - 脱敏文件实体
@objc(RedactedFile)
public class RedactedFile: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var fileTypeRaw: String
    @NSManaged public var filePath: String
    @NSManaged public var originalFileId: UUID
    @NSManaged public var redactedAt: Date
    @NSManaged public var fileSize: Int64
    
    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .image }
        set { fileTypeRaw = newValue.rawValue }
    }
}

// MARK: - 敏感区域（内存模型，不持久化）
struct SensitiveRegion: Identifiable {
    let id = UUID()
    let type: SensitiveType
    let boundingBox: CGRect
    let confidence: Float
    let pageIndex: Int?  // PDF多页支持
    var isConfirmed: Bool = false
    let recognizedText: String?
}

enum SensitiveType: String, Codable {
    case phoneNumber = "phone"
    case email = "email"
    case idCard = "id_card"
    case bankCard = "bank_card"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .phoneNumber: return "手机号"
        case .email: return "邮箱"
        case .idCard: return "身份证"
        case .bankCard: return "银行卡"
        case .custom: return "自定义"
        }
    }
    
    var icon: String {
        switch self {
        case .phoneNumber: return "📱"
        case .email: return "📧"
        case .idCard: return "🆔"
        case .bankCard: return "💳"
        case .custom: return "🔒"
        }
    }
}
```

---

## 编辑引擎

### 图片编辑器（现有）

```swift
class ImageRedactionEditor: RedactionEditor {
    typealias FileType = OriginalImage
    
    @Published var currentImage: UIImage?
    @Published var editHistory: [EditOperation] = []
    @Published var redoStack: [EditOperation] = []
    
    func loadFile(_ file: OriginalImage) async throws {
        // 解密并加载图片
        // ... 现有实现
    }
    
    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        guard let image = currentImage else { return [] }
        
        // 使用ImageOCRRecognizer
        let recognizer = ImageOCRRecognizer()
        let data = image.pngData() ?? Data()
        let texts = try await recognizer.recognizeText(in: data, fileType: .image)
        
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
    
    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        // 现有图片脱敏逻辑
        // ...
    }
    
    func undo() { /* ... */ }
    func redo() { /* ... */ }
    
    func exportRedactedFile() async throws -> Data {
        guard let finalImage = currentImage else {
            throw EditorError.noImageLoaded
        }
        return finalImage.pngData() ?? Data()
    }
}
```

---

### PDF编辑器 🆕

```swift
import PDFKit

class PDFRedactionEditor: RedactionEditor, ObservableObject {
    typealias FileType = OriginalPDF
    
    @Published var pdfDocument: PDFDocument?
    @Published var currentPageIndex: Int = 0
    @Published var redactionAnnotations: [Int: [PDFAnnotation]] = [:]  // 页码 -> 注释列表
    
    private var originalFile: OriginalPDF?
    
    // MARK: - 加载文件
    func loadFile(_ file: OriginalPDF) async throws {
        self.originalFile = file
        
        // 解密PDF数据
        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: file.encryptedDataPath))
        let decryptedData = try CryptoEngine.shared.decrypt(data: encryptedData)
        
        // 加载PDF
        guard let document = PDFDocument(data: decryptedData) else {
            throw EditorError.invalidPDFData
        }
        
        await MainActor.run {
            self.pdfDocument = document
            self.currentPageIndex = 0
        }
    }
    
    // MARK: - 智能识别敏感区域
    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        guard let document = pdfDocument else { return [] }
        
        var allRegions: [SensitiveRegion] = []
        
        // 遍历所有页面
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageContent = page.string else { continue }
            
            // 正则匹配敏感信息
            let patterns: [(pattern: String, type: SensitiveType)] = [
                (SensitivePatterns.phoneNumber, .phoneNumber),
                (SensitivePatterns.email, .email),
                (SensitivePatterns.idCard, .idCard),
                (SensitivePatterns.bankCard, .bankCard)
            ]
            
            for (pattern, type) in patterns {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(in: pageContent, range: NSRange(pageContent.startIndex..., in: pageContent))
                
                for match in matches {
                    // 获取匹配的文字
                    let matchedText = String(pageContent[Range(match.range, in: pageContent)!])
                    
                    // 在PDF中找到这段文字的位置
                    if let selections = page.findString(matchedText, withOptions: .caseInsensitive),
                       let firstSelection = selections.first {
                        let bounds = firstSelection.bounds(for: page)
                        
                        allRegions.append(SensitiveRegion(
                            type: type,
                            boundingBox: bounds,
                            confidence: 1.0,
                            pageIndex: pageIndex,
                            isConfirmed: false,
                            recognizedText: matchedText
                        ))
                    }
                }
            }
        }
        
        return allRegions
    }
    
    // MARK: - 应用脱敏
    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        guard let document = pdfDocument,
              let page = document.page(at: currentPageIndex) else { return }
        
        // 创建Redaction注释
        let annotation = PDFAnnotation(bounds: region, forType: .redact, withProperties: nil)
        
        // 根据效果设置样式
        switch effect {
        case .solidBlack:
            annotation.color = .black
        case .rectangle(let color, _):
            annotation.color = color
        default:
            annotation.color = .black
        }
        
        // 添加到页面
        page.addAnnotation(annotation)
        
        // 记录注释（用于撤销）
        if redactionAnnotations[currentPageIndex] == nil {
            redactionAnnotations[currentPageIndex] = []
        }
        redactionAnnotations[currentPageIndex]?.append(annotation)
    }
    
    // MARK: - 撤销/重做
    func undo() {
        guard let document = pdfDocument,
              let page = document.page(at: currentPageIndex),
              var annotations = redactionAnnotations[currentPageIndex],
              let lastAnnotation = annotations.popLast() else { return }
        
        page.removeAnnotation(lastAnnotation)
        redactionAnnotations[currentPageIndex] = annotations
    }
    
    func redo() {
        // PDF编辑器的重做逻辑
        // ...
    }
    
    // MARK: - 导出脱敏文件
    func exportRedactedFile() async throws -> Data {
        guard let document = pdfDocument else {
            throw EditorError.noPDFLoaded
        }
        
        // 应用所有Redaction（永久删除底层文字）
        for pageIndex in 0..<document.pageCount {
            document.page(at: pageIndex)?.applyRedactions()
        }
        
        // 导出为Data
        guard let data = document.dataRepresentation() else {
            throw EditorError.exportFailed
        }
        
        return data
    }
    
    // MARK: - PDF特有功能
    func goToPage(_ pageIndex: Int) {
        guard let document = pdfDocument,
              pageIndex >= 0 && pageIndex < document.pageCount else { return }
        
        currentPageIndex = pageIndex
    }
    
    func getTotalPages() -> Int {
        return pdfDocument?.pageCount ?? 0
    }
}
```

---

## 存储架构

### 文件系统布局（扩展版）

```
Documents/
├── Originals/               # 加密原文件
│   ├── Images/              # 图片文件
│   │   ├── 123e4567.enc
│   │   └── ...
│   └── PDFs/                # PDF文件 🆕
│       ├── 789abcde.enc
│       └── ...
├── Thumbnails/              # 加密缩略图
│   ├── Images/
│   │   ├── 123e4567_thumb.enc
│   │   └── ...
│   └── PDFs/                # PDF缩略图 🆕
│       ├── 789abcde_thumb.enc
│       └── ...
├── Redacted/                # 脱敏文件（明文）
│   ├── Images/
│   │   ├── aabbccdd.png
│   │   └── ...
│   └── PDFs/                # 脱敏PDF 🆕
│       ├── eeff0011.pdf
│       └── ...
└── Database/
    └── ZeroNetRedact.sqlite # Core Data数据库
```

### 存储管理器（扩展版）

```swift
class StorageManager {
    static let shared = StorageManager()
    
    private let baseURL: URL
    private let originalsURL: URL
    private let thumbnailsURL: URL
    private let redactedURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseURL = docs
        
        originalsURL = docs.appendingPathComponent("Originals")
        thumbnailsURL = docs.appendingPathComponent("Thumbnails")
        redactedURL = docs.appendingPathComponent("Redacted")
        
        createDirectoryStructure()
    }
    
    // MARK: - 创建目录结构
    private func createDirectoryStructure() {
        let dirs = [
            originalsURL.appendingPathComponent("Images"),
            originalsURL.appendingPathComponent("PDFs"),
            thumbnailsURL.appendingPathComponent("Images"),
            thumbnailsURL.appendingPathComponent("PDFs"),
            redactedURL.appendingPathComponent("Images"),
            redactedURL.appendingPathComponent("PDFs")
        ]
        
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 存储加密原文件
    func saveEncryptedOriginal(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let url = originalsURL.appendingPathComponent(subdir).appendingPathComponent("\(id.uuidString).enc")
        try data.write(to: url, options: .atomicWrite)
        return url
    }
    
    // MARK: - 存储脱敏文件
    func saveRedactedFile(data: Data, id: UUID, type: FileType) throws -> URL {
        let subdir: String
        let ext: String
        
        switch type {
        case .image:
            subdir = "Images"
            ext = "png"
        case .pdf:
            subdir = "PDFs"
            ext = "pdf"
        }
        
        let url = redactedURL.appendingPathComponent(subdir).appendingPathComponent("\(id.uuidString).\(ext)")
        try data.write(to: url, options: .atomicWrite)
        return url
    }
    
    // MARK: - 获取文件URL
    func getOriginalURL(for id: UUID, type: FileType) -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        return originalsURL.appendingPathComponent(subdir).appendingPathComponent("\(id.uuidString).enc")
    }
    
    func getRedactedURL(for id: UUID, type: FileType) -> URL {
        let subdir = type == .image ? "Images" : "PDFs"
        let ext = type == .image ? "png" : "pdf"
        return redactedURL.appendingPathComponent(subdir).appendingPathComponent("\(id.uuidString).\(ext)")
    }
}
```

---

## PDF扩展实现详细方案

### 方案A：PDF转图片（V1.5快速实现）

```swift
class PDFToImageConverter {
    // PDF页面渲染为图片
    func convertToImages(pdfData: Data) async throws -> [UIImage] {
        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.invalidPDF
        }
        
        var images: [UIImage] = []
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            let pageRect = page.bounds(for: .mediaBox)
            let image = renderPage(page, in: pageRect)
            images.append(image)
        }
        
        return images
    }
    
    private func renderPage(_ page: PDFPage, in rect: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(rect)
            
            ctx.cgContext.translateBy(x: 0, y: rect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
```

### 方案B：原生PDF脱敏（V2.0完整实现）

**详见上文 PDFRedactionEditor 实现**

---

## 性能优化

### 1. PDF多页异步加载

```swift
class PDFPageCache {
    static let shared = PDFPageCache()
    private var cache = NSCache<NSNumber, PDFPage>()
    
    func cachePage(_ page: PDFPage, at index: Int) {
        cache.setObject(page, forKey: NSNumber(value: index))
    }
    
    func getCachedPage(at index: Int) -> PDFPage? {
        return cache.object(forKey: NSNumber(value: index))
    }
}
```

### 2. PDF缩略图预加载

```swift
class PDFThumbnailGenerator {
    func generateThumbnails(for document: PDFDocument) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage).self) { group in
            for index in 0..<document.pageCount {
                group.addTask {
                    guard let page = document.page(at: index) else {
                        return (index, UIImage())
                    }
                    let thumbnail = page.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
                    return (index, thumbnail)
                }
            }
            
            var thumbnails: [UIImage] = Array(repeating: UIImage(), count: document.pageCount)
            for await (index, thumbnail) in group {
                thumbnails[index] = thumbnail
            }
            return thumbnails
        }
    }
}
```

---

## 安全设计

### PDF特定安全考虑

1. **元数据清理**：脱敏时清除PDF元数据（作者、创建时间等）
2. **嵌入对象**：检查PDF中的嵌入文件和JavaScript
3. **加密PDF**：支持导入已加密的PDF

```swift
class PDFSanitizer {
    func sanitizeMetadata(document: PDFDocument) {
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Redacted Document",
            PDFDocumentAttribute.authorAttribute: "",
            PDFDocumentAttribute.creatorAttribute: "ZeroNet Redact",
            PDFDocumentAttribute.producerAttribute: ""
        ]
    }
    
    func removeEmbeddedFiles(document: PDFDocument) {
        // 检查并移除嵌入的文件
        // ...
    }
}
```

---

## 总结

### 架构扩展性总结

| 扩展点 | 实现方式 | 难度 |
|--------|---------|------|
| **新文件类型** | 实现Protocol | 低 ⭐ |
| **新编辑器** | 继承抽象类 | 中 ⭐⭐ |
| **新识别算法** | 插件模式 | 低 ⭐ |
| **新存储方式** | 策略模式 | 中 ⭐⭐ |

### V3.0架构核心优势

✅ **完全无修改扩展**：添加PDF支持不修改现有图片代码  
✅ **类型安全**：Protocol + 泛型确保编译期检查  
✅ **高内聚低耦合**：每个模块职责单一  
✅ **易于测试**：Protocol可mock  
✅ **未来可扩展**：视频、Word、Excel等

---

**架构设计完成**  
**支持V1.0图片脱敏 + V1.5/V2.0无缝扩展PDF脱敏**
