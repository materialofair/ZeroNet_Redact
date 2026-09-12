# 视频脱敏性能诊断

2026-09-12：用户报告 iPhone 15 Pro 处理慢，尚无原始素材、分阶段耗时或真机 Instruments 录制。以下是代码证据，不能等同于已测得的性能提升。

## 已处理

- 分析原来循环调用 `AVAssetImageGenerator.copyCGImage`，每个采样点单独请求截图、创建 CGImage 和 Vision request。改用 AVAssetReaderVideoCompositionOutput 顺序读取已旋转、缩放的像素缓冲，复用 Vision request，避免应用层逐帧截图。
- 保留长边 1280 和既有采样策略；不为提速减少识别次数。
- 开始导出暂停预览，避免两路视频解码和贴纸合成竞争。
- 分析取消传递到后台任务；解码或识别错误中止分析，不能当作“无人脸”。
- `VideoPerformance` 日志记录分析帧数、读取/Vision/总耗时，以及导出总耗时、结束时温度等级和低电量模式。日志不包含视频路径、图像或人脸坐标。

顺序合成输出 API：[Apple 文档](https://developer.apple.com/documentation/avfoundation/avassetreadervideocompositionoutput)。

## 真机验证与设备适配依据

使用同一素材、同一系统、同一导出设置，对修改前后 Release 构建各运行三次，区分首次模型加载与后续运行，记录中位数。建议覆盖 1080p/4K、30/60fps、横竖屏、多人小脸、快速运动与长视频。

在 Xcode Console 按 `VideoPerformance` 筛选：

- `readSeconds` 高：检查解码/缩放，结合 Instruments 和原始编码格式验证。
- `visionSeconds` 高：识别为主要成本；引入检测+跟踪之前必须验证短暂出现人脸和快速移动覆盖率。
- `export totalSeconds` 高：检查原分辨率合成和编码；HEVC 不一定比 H.264 快。
- 用 Instruments 记录峰值内存、温度变化和媒体/GPU 负载，避免把发热降频误判成某型号始终性能不足。

本次没有引入未经实测的机型白名单或自动降画质。若真机数据确认编码/温度瓶颈，再增加用户可见的 1080p 快速导出选项；设备能力与运行时状态决定建议，识别密度不应随手机档位静默下降。

## 已知边界

- 原有长视频最低 2fps + 最近邻脸框不能保证捕获快速移动或短暂出现的人脸；本次未解决该问题。
- 取消在当前解码/Vision 调用返回后生效。
- 新增测试验证完整读取、竖屏尺寸、60fps 输入采样和预取消；现有导出测试验证遮挡像素、音轨、方向与时长。合成测试素材不等同于真实人脸检出率验证。

## 本次验证

运行命令（仓库根目录）：

```sh
xcodebuild -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,id=72367FCE-DFD3-4F3C-AE6D-2A64BD24976F' -parallel-testing-enabled NO -derivedDataPath /tmp/zeronet-video-perf-build -only-testing:zeroNetRedactTests/VideoFaceAnalyzerTests -only-testing:zeroNetRedactTests/VideoExporterTests -only-testing:zeroNetRedactTests/VideoExporterRedactionTests test CODE_SIGNING_ALLOWED=NO
git diff --check
```

结果：10 项测试全部通过，0 失败；diff 空白检查通过。首次模拟器测试的 Vision 出现 `Could not create inference context`；仅模拟器启用 CPU 推理后全部通过，真机仍使用默认计算设备选择。此处结果不是 iPhone 15 Pro 性能基准。

日志：`/tmp/zeronet-video-test3.log`。

改动文件（仓库相对路径）：

- `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoFaceAnalyzer.swift`
- `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoExporter.swift`
- `zeroNetRedact/zeroNetRedact/Views/Video/VideoEditorViewModel.swift`
- `zeroNetRedact/zeroNetRedactTests/VideoFaceAnalyzerTests.swift`
- `docs/performance/video-redaction.md`
