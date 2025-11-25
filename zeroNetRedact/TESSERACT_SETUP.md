# TesseractOCR 集成指南

本文档说明如何安装TesseractOCRiOS和配置中文语言包。

## 1. 安装CocoaPods依赖

在项目根目录(`zeroNetRedact/`)执行:

```bash
cd /Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet\ Redact/zeroNetRedact

# 安装CocoaPods (如果未安装)
sudo gem install cocoapods

# 安装项目依赖
pod install
```

**重要**: 安装完成后，请使用 `zeroNetRedact.xcworkspace` 打开项目，而不是 `.xcodeproj` 文件。

## 2. 下载中文语言包

TesseractOCR需要语言包才能识别文字。我们需要中文简体 + 英文语言包。

### 方法1: 自动下载脚本 (推荐)

在项目目录执行:

```bash
cd /Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet\ Redact/zeroNetRedact/zeroNetRedact

# 创建tessdata目录
mkdir -p Resources/tessdata

# 下载中文简体语言包
curl -L https://github.com/tesseract-ocr/tessdata/raw/main/chi_sim.traineddata \
     -o Resources/tessdata/chi_sim.traineddata

# 下载英文语言包
curl -L https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata \
     -o Resources/tessdata/eng.traineddata

echo "✅ 语言包下载完成！"
```

### 方法2: 手动下载

1. **创建目录**: `zeroNetRedact/Resources/tessdata/`

2. **下载文件**:
   - 中文简体: https://github.com/tesseract-ocr/tessdata/raw/main/chi_sim.traineddata
   - 英文: https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata

3. **放置文件**: 将下载的 `.traineddata` 文件放入 `Resources/tessdata/` 目录

## 3. 添加语言包到Xcode项目

1. 在Xcode中，右键点击 `zeroNetRedact` 项目
2. 选择 **Add Files to "zeroNetRedact"...**
3. 导航到 `Resources/tessdata/` 目录
4. 选中 `chi_sim.traineddata` 和 `eng.traineddata`
5. 确保勾选:
   - ✅ **Copy items if needed**
   - ✅ **Create folder references** (不是Create groups!)
   - ✅ **Add to targets: zeroNetRedact**
6. 点击 **Add**

## 4. 验证安装

### 检查文件是否正确添加

在Xcode左侧导航栏，应该看到:

```
zeroNetRedact/
├── Resources/
│   └── tessdata/
│       ├── chi_sim.traineddata
│       └── eng.traineddata
```

文件夹图标应该是**蓝色**的(folder reference)，不是黄色的(group)。

### 检查Build Phases

1. 在Xcode中选择项目
2. 选择 **zeroNetRedact** target
3. 进入 **Build Phases** 标签
4. 展开 **Copy Bundle Resources**
5. 确认看到:
   - ✅ `chi_sim.traineddata`
   - ✅ `eng.traineddata`

## 5. 测试识别

编译运行项目后:

1. 导入一张包含中文的图片
2. 点击 **AI检测** 按钮
3. 查看控制台输出:

```
✅ TesseractOCR初始化成功
📝 Tesseract识别到文本: 342222199910216550
✅ Tesseract识别完成，共 1 个文本块
🔴 敏感区域[0]: 身份证
```

## 6. 常见问题

### 问题1: "Could not initialize Tesseract"

**原因**: 语言包未正确添加到项目

**解决**:
- 确认语言包在 `Resources/tessdata/` 目录
- 重新添加文件到Xcode (确保选择 "Create folder references")
- Clean Build Folder (Cmd + Shift + K)

### 问题2: "Language not found"

**原因**: 语言包文件名错误或路径不对

**解决**:
- 检查文件名: 必须是 `chi_sim.traineddata` 和 `eng.traineddata`
- 检查目录结构: 必须在 `tessdata/` 文件夹下
- 确认文件出现在 Copy Bundle Resources 中

### 问题3: 识别准确度低

**优化建议**:
1. 确保图片清晰，分辨率足够
2. 图片对比度要高
3. 文字要水平放置（不要倾斜）
4. 可以调整 `TesseractOCRRecognizer.swift` 中的预处理参数

## 7. 文件大小

- `chi_sim.traineddata`: ~25MB
- `eng.traineddata`: ~5MB
- **总计**: ~30MB (会增加App包体积)

## 8. 切换到Apple Vision (可选)

如果TesseractOCR效果不理想，可以切换回Apple Vision:

在 `TextRecognizer.swift` 中:

```swift
class ImageOCRRecognizer: TextRecognition {
    private let useTesseract = false  // 改为 false
    ...
}
```

## 完成！

现在你的App已经集成了离线、高精度的TesseractOCR识别引擎。

所有识别都在本地完成，身份证信息绝不上传到云端，完全保护用户隐私。
