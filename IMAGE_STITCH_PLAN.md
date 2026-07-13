# 多图拼接长图功能设计(Stitch)

> 应用:ZeroNet Redact(零网隐私)
> 日期:2026-07-13
> 状态:设计稿,待评审
> 定位:把多张截图竖向拼接为一张长图,随后进入现有脱敏流程 —— "拼接聊天记录长图并一键打码" 是市场上 Picsew(只拼不脱敏)与各类打码 App(只脱敏不拼接)之间的空白组合。

---

## 1. 调研结论

### 1.1 竞品 Picsew(App Store 编辑精选,4.7 分 / 3100+ 评分)

| 维度 | Picsew 做法 |
|------|------------|
| 核心拼接 | 自动检测相邻截图重叠区域并拼接,支持手动微调拼缝;竖向 + 横向;单次最多 300 张 |
| 进阶功能 | 滚动录屏生成长图、网页整页截图、标注/模糊/水印/设备边框、PDF 导出 |
| 定价 | 免费版(基础拼接)+ **Plus $0.99**(标注、边框、高质量导出)+ **Pro $1.99**(录屏滚动截图、网页截图),均为一次性买断 |

要点:Picsew 的护城河是"自动重叠检测"的体验——用户选完图直接得到无缝长图,检测失败才需要手动调。我们对标的正是这一点,但**不做**它的全家桶(录屏、网页截图、设备边框),那些与脱敏定位无关。

### 1.2 本项目现状(与新功能相关)

- **接入点极干净**:拼好的长图编码为 `Data` → `ImportManager.shared.importFile(from: .imageData(data))` 即自动走 SHA256 去重、AES 加密落盘、生成 `OriginalImage` 记录,用户点击即可用现有 `SimpleBrushEditor` 脱敏。编辑器接口无需改动。
- **入口位置**:`Views/Import/Components/ImportButtonBar.swift` 目前两个按钮(选图片/选 PDF),加第三个"拼长图"最自然;`ImportEmptyStateView` 同步加引导。
- **付费体系**:StoreKit 2,单一非消耗型买断 `com.zeronet.redact.premium`($3.99,"无限制脱敏");免费用户每日 3 次图片导出 + 3 次文档导出(`UsageTracker`);判定统一走 `AppState.hasUnlimitedAccess`(含审核模式);配额触顶弹 `PremiumView`。
- **最大技术风险 —— 现有编辑器对超大图会 OOM**(以 1170×30000 长图为例,单份 RGBA 位图 ≈ 140MB):
  1. `ImageRedactionEditor` 同时持有 `originalImage` + `currentImage`,`EditorViewModel` 再持一份(3 份整图);
  2. 每次打码 `UIGraphicsImageRenderer(size: 原图全尺寸)` 全图重绘;
  3. 撤销从原图全量重放历史,每步一张全尺寸位图;
  4. OCR 把整图丢给单个 `VNRecognizeTextRequest`,无分块;
  5. 导入时 `UIImage(data:)` 解码全图做缩略图/元数据;
  6. 导出 `pngData()` 整图编码;
  7. 显示层 `Image(uiImage:)` 全分辨率常驻。

  → 设计必须**限制拼接输出的总像素数**,并对长图 OCR 做分块;编辑器整体 tile 化改造放 V2。

---

## 2. 目标与范围

### V1 目标

1. 从相册多选 2–20 张图,竖向拼接为一张长图。
2. **自动重叠检测**(对标 Picsew):自动识别相邻截图的重叠区域与固定页眉/页脚(状态栏、导航栏、Tab 栏),拼出无缝长图;检测不可靠时降级为简单堆叠。
3. **手动调整**:拖拽排序;每个拼缝可手动调整两侧裁剪线。
4. 生成的长图进入现有导入管线(加密入库),可直接跳转脱敏编辑器。
5. 长图的 AI 敏感信息识别可用(OCR 分块)。

### 非目标(V2+ 或永不做)

- 横向拼接(V2,引擎预留方向参数)
- 滚动录屏生成长图、网页整页截图(Picsew Pro 功能,与脱敏定位弱相关,不做)
- 标注、水印、设备边框(不做,保持产品聚焦)
- 300 张批量(内存不允许,20 张上限已覆盖绝大多数聊天记录场景)
- 编辑器全面 tile 化改造(V2,V1 用尺寸上限规避)

---

## 3. 方案比选

### 方案 A:纯手动拼接(MVP 最小化)

用户排序后,默认零重叠直接堆叠,每个拼缝手动拖裁剪线。
✅ 无算法风险、开发量最小;❌ 体验远逊 Picsew,"手动裁 19 个拼缝"基本不可用,差评风险高。

### 方案 B:自动重叠检测 + 手动兜底(推荐)✅

核心算法(`OverlapDetector`):
1. **行指纹**:每张图按行降采样为特征向量(每行采样 N=64 个点的灰度值,或逐行 hash);
2. **固定区检测**:对比全组图片,顶部/底部连续相同的行区域判定为固定页眉/页脚(状态栏时间变化用容差处理),拼接时中间图裁掉;
3. **重叠搜索**:对相邻两图,在上图尾部与下图头部窗口内做行指纹相似度搜索(归一化互相关),得到最优偏移与置信度;
4. **置信度门限**:低于门限的拼缝降级为零重叠堆叠,并在 UI 上标黄提示用户手动调。

✅ Picsew 级体验、算法自研可控、全离线(符合产品"零网络"心智);❌ 开发量中等,需要真机截图集调参。

### 方案 C:Vision 框架配准(`VNTranslationalImageRegistrationRequest`)

用系统 API 做两图平移配准。
✅ 代码少;❌ 该 API 面向自然图像对齐,对"截图 + 固定页眉页脚 + 状态栏时间跳变"场景不可控,无法输出裁剪语义(它给的是平移量,不是"裁掉固定区"),置信度不可解释。社区实践普遍反馈截图场景准确率不如定制行匹配。

**结论:采用方案 B**,行指纹算法本身 ~200 行纯函数,可充分单测。

---

## 4. 架构设计

遵循现有 MVVM + BusinessLogic 单例分层,新增模块:

```
BusinessLogic/Stitch/
├── StitchEngine.swift        // 编排:输入源图列表 → StitchPlan → 渲染输出 Data
├── OverlapDetector.swift     // 纯算法:行指纹、固定区检测、重叠搜索(可独立单测)
└── StitchRenderer.swift      // 全分辨率分块渲染 + 编码(内存安全)

Views/Stitch/
├── StitchEditorView.swift    // 主界面:预览、排序、拼缝调整、生成
├── SeamAdjustView.swift      // 单个拼缝的精调界面(双图对照 + 拖拽裁剪线)
└── StitchModels.swift        // StitchPlan / SeamConfig / 置信度等 UI 模型
```

### 4.1 核心数据模型

```swift
/// 一次拼接的完整方案(算法产出,用户可改)
struct StitchPlan {
    var items: [StitchItem]          // 有序源图
    struct StitchItem {
        let sourceID: UUID           // 对应降采样缓存与原图 PHPickerItem
        let pixelSize: CGSize        // 原始像素尺寸
        var cropTop: CGFloat         // 顶部裁剪(像素,含固定页眉与重叠区)
        var cropBottom: CGFloat      // 底部裁剪
        var seamConfidence: Float    // 与上一张的拼缝置信度(0 = 手动/堆叠)
    }
    var outputScale: CGFloat         // 超限时的整体缩放系数(≤1)
}
```

### 4.2 数据流

```
PhotosPicker 多选(2–20 张)
  → 降采样加载预览图(ImageIO CGImageSourceCreateThumbnailAtIndex,宽 ≤ 750px)
  → OverlapDetector 后台计算 StitchPlan(基于降采样图,坐标按比例映射回原图)
  → StitchEditorView 预览(LazyVStack 逐张显示裁剪后的预览图,不合成整图)
  → 用户排序 / 调拼缝(实时更新 StitchPlan)
  → StitchRenderer 全分辨率渲染 → JPEG(q0.9) Data
  → ImportManager.importFile(from: .imageData(data))(复用去重/加密/缩略图/落库)
  → Toast + 可选直接打开 SimpleBrushEditor 脱敏
```

### 4.3 内存策略(硬约束)

| 环节 | 策略 |
|------|------|
| 预览 | 永不合成整图;`LazyVStack` 按 `StitchItem` 逐张渲染降采样图,裁剪用 `.frame + .clipped` 视觉实现 |
| 检测 | 全部在降采样图(宽 ≤750px)上计算,行指纹内存可忽略 |
| 渲染导出 | 单个 `CGBitmapContext` 一次性分配输出位图,`autoreleasepool` 内逐张解码原图 → 绘制 → 立即释放;任何时刻内存 ≈ 输出位图 + 单张源图 |
| **输出尺寸上限** | **总像素 ≤ 3000 万**(如 1170 宽 ≈ 25600px 高,位图 ~115MB;后续编辑器 3 份拷贝 ~345MB,iOS 26 目标机型可承受)。超限时按 `outputScale` 整体降宽渲染(Picsew 同做法),UI 明示"已缩放至 xx%" |
| 高度上限 | 输出高 ≤ 65000px(JPEG 上限 65535 兜底) |
| 长图 OCR | `ImageOCRRecognizer` 增加分块路径:高 > 8192px 时按 4096px 高、10% 重叠切片,逐片 `VNRecognizeTextRequest`,归一化坐标映射合并,跨片重复检出去重(复用现有 `deduplicateRegions`) |
| 导入缩略图 | `ImageImportProcessor` 的 `UIImage(data:)` 整图解码改为 ImageIO 降采样(顺手修复,同样惠及普通大图导入) |

### 4.4 对现有代码的改动面(刻意最小)

| 文件 | 改动 |
|------|------|
| `ImportButtonBar.swift` / `ImportView.swift` / `ImportEmptyStateView.swift` | 加"拼长图"入口按钮 + sheet 接线 |
| `TextRecognizer.swift`(`ImageOCRRecognizer`) | 新增大图分块 OCR 路径(高 ≤8192px 走原路径,行为不变) |
| `FileImportProcessor.swift` | 缩略图/元数据改 ImageIO 降采样(行为等价) |
| `Localizable.strings` ×2 | 新增 `stitch.*` 键 |
| 其余 | 全部为新增文件,不触碰编辑器/存储/加密 |

---

## 5. 交互设计

1. **入口**:导入页底部第三个按钮"拼长图"(icon: `rectangle.stack.badge.plus` 之类);空状态页加同款引导。
2. **选图**:系统 `PhotosPicker`,`maxSelectionCount` 按付费状态 4 或 20(见 §6),少于 2 张不可进入。
3. **拼接编辑页**(`StitchEditorView`,fullScreenCover):
   - 进入即显示"智能拼接中…"(后台跑检测,降采样图上通常 <1s);
   - 完成后纵向滚动预览拼接效果;每个拼缝处悬浮小手柄:绿色 = 自动检测成功,黄色 = 低置信度(已降级堆叠,建议手动调);
   - 点拼缝手柄 → `SeamAdjustView`:上下两张图放大对照,拖动两条裁剪线,实时预览衔接效果;
   - 长按缩略图条拖拽排序(排序后该项相邻拼缝重新检测);
   - 顶部:取消 / 标题;底部主按钮:"生成长图"。
4. **生成后**:进度环(渲染 + 加密入库)→ 成功弹窗两个动作:**"去脱敏"**(直接打开 `SimpleBrushEditor`)/ "留在导入列表"。源截图不删除(与现有导入行为一致,由用户自行管理相册)。
5. **失败与边界**:单张非同宽图 → 拼接时按最窄宽度等比缩放对齐(提示);全部检测失败 → 零重叠堆叠仍可用;渲染失败/内存告警 → 建议减少张数。

---

## 6. 付费策略(调研 + 建议)

### 分析

- Picsew 证明拼接功能本身有独立付费意愿($0.99–1.99 买断,大量付费用户);
- 本 App 的差异化不是"拼得比 Picsew 好",而是**"拼完即可打码"的闭环**——聊天记录长图分享前打码是高频刚需场景,该组合目前市场空白;
- 现有商业模型是"功能免费、导出限额、$3.99 买断无限",新功能应强化而非复杂化这一模型(不新增 SKU、不引订阅)。

### 候选方案

| 方案 | 内容 | 评估 |
|------|------|------|
| a. 完全免费 | 拼接不限,导出走现有每日配额 | 拉新最强,但白送了最大差异化卖点,浪费转化杠杆 |
| b. 张数分层 ✅ | **免费:单次最多 4 张**,拼接结果计入每日 3 次图片配额;**Premium:单次 20 张 + 无限次** | 轻度用户完整体验闭环;聊天记录场景动辄 5 张以上,是自然的付费触发点;实现只需在选图和导出两处判 `hasUnlimitedAccess` |
| c. 纯 Premium | 免费只能预览不能导出 | 转化最陡但口碑差,免费用户无法体验核心价值 |

### 建议:方案 b

- 免费版:单次 ≤4 张,生成长图计 1 次每日图片导出配额(复用 `UsageTracker.canExportImage`/`recordImageExport`);
- Premium(现有 $3.99 买断,不加价不加 SKU):单次 ≤20 张、不限次数;
- 选图超 4 张或配额触顶时弹现有 `PremiumView`(带"购买成功自动继续"回调,与编辑器导出同模式);
- Paywall 文案增加"多图拼接长图"权益点;上架材料(`APP_STORE_COPY.md`)副标题/关键词加入"长截图/拼图/拼接"提升 ASO;
- 后续观察:若拼接显著拉动转化,可评估把买断价从 $3.99 上调至 $5.99(老用户不受影响,买断制涨价无迁移成本)。

---

## 7. 测试计划

| 测试 | 内容 |
|------|------|
| `OverlapDetectorTests` | 程序化渲染两张带已知重叠区的"伪截图"(参考 `SensitiveDetectionTests` 的渲染方式),断言检测偏移误差 ≤2px;含状态栏时间变化容差用例、无重叠用例(置信度应低)、固定页眉/页脚裁剪用例 |
| `StitchRendererTests` | 4 张 1170×2532 拼接:输出尺寸正确、接缝像素与源图一致;20 张超限场景:`outputScale` 生效、总像素 ≤3000 万 |
| `StitchImportIntegrationTests` | 拼接产物走 `ImportManager` 全流程:入库、加密、缩略图、Core Data 记录正确 |
| 长图 OCR 分块测试 | 渲染 1170×20000 含敏感信息(手机号/邮箱/身份证,分布在头/中/尾)的长图,断言分块 OCR 全部检出且坐标正确(扩展现有 `SensitiveDetectionTests` 模式) |
| 配额门控测试 | 免费 4 张上限、配额扣减、`hasUnlimitedAccess` 旁路 |
| 真机手测 | 内存峰值(Instruments)、20 张真实聊天截图拼接准确率、脱敏编辑器打开 3000 万像素长图不崩 |

---

## 8. 里程碑

| 阶段 | 内容 | 交付 |
|------|------|------|
| M1 引擎 | `OverlapDetector` + `StitchRenderer` + 单测 | 算法准确率、内存达标 |
| M2 界面 | `StitchEditorView` / `SeamAdjustView` / 入口接线 | 完整交互可用 |
| M3 打通 | 导入管线接入 + 配额/Paywall + 本地化 | 端到端闭环 |
| M4 长图适配 | OCR 分块 + 导入降采样修复 + 真机内存验证 | 长图脱敏可用 |
| M5 发布 | 上架文案更新、TestFlight 回归 | 提审 |

---

## 附:调研来源

- [Picsew - App Store](https://apps.apple.com/us/app/picsew-screenshot-stitching/id1208145167)(功能、内购 Plus $0.99 / Pro $1.99、4.7 分)
- [Picsew 官方文档](https://docs.picsew.app/)
- [TidBITS: Picsew Is Indispensable for Professional iOS Screenshots](https://tidbits.com/2020/08/28/picsew-is-indispensable-for-professional-ios-screenshots/)
- [Michael Tsai - Picsew 3.5(Standard→Plus 更名与分层)](https://mjtsai.com/blog/2020/09/01/picsew-3-5/)
