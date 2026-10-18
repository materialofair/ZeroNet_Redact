# 1.5.1 新图标与全媒体脱敏发布记录

2026-09-26 22:40（上海时区）。1.5.1（14）已正式提交，App Store Connect 显示“正在等待审核”，成功提示“已提交 1 个项目”。包含已选新图标；审核通过后自动发布。用户明确授权取消法国销售，供应地区已由 174 改为 173，法国显示“正在处理为不可用”（Apple 提示 24 小时内生效）。

提交记录 ID：`ca66c370-b78e-49d0-9ccb-6aab0ba7e617`。

下列早期构建 13 和 PDF 优先记录为历史过程；最终定位为照片、视频、文档脱敏并列，以“构建 14 更新”和本文当前状态为准。

## 已完成

- App 版本 1.5.1，上传构建号 13；归档和 App Store 发行导出成功。
- App Store Connect 创建 1.5.1 草稿。保存英语推广文本、PDF 优先长描述、英文官网地址及更新说明；保存中文官网地址和更新说明。名称、副标题、关键词、价格和免费额度未调整。
- 年龄问卷核查：源码中没有内置任意网页浏览器或广告模块，外部网页入口为 SwiftUI Link。将“不受限的网页访问”和“广告”改为否，其余答案保持；Apple 计算分级 4+，新版本发布前公开页面可能仍为 16+。
- 真实英文截图 3 张，1320×2868，拍摄于 iPhone 17 Pro Max / iOS 26.5 模拟器。未合成 App 界面，样例文档全部为虚构内容。
- 原稿和实际导出副本分别位于 `../../../output/pdf/pdf-privacy-demo.pdf`、`../../../output/pdf/pdf-privacy-demo-redacted.pdf`。

## 验证证据

签名测试命令：

```sh
xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,id=302840E8-B554-4444-8723-5A8A2C699C15' -derivedDataPath /tmp/redact-151-build -resultBundlePath /tmp/redact-151-signed-tests.xcresult -only-testing:zeroNetRedactTests/MuPDFRedactorTests -only-testing:zeroNetRedactTests/TextSearchTests -only-testing:zeroNetRedactTests/PDFReviewNavigatorTests -parallel-testing-enabled NO
```

结果：12/12 通过。首次关闭签名的运行出现 Keychain 权限错误 -34018；恢复正常签名后通过，未为此修改业务代码。

```sh
xcodebuild archive -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/ZeroNetRedact-1.5.1-13.xcarchive -derivedDataPath /tmp/redact-151-device CURRENT_PROJECT_VERSION=13
xcodebuild -exportArchive -archivePath /tmp/ZeroNetRedact-1.5.1-13.xcarchive -exportOptionsPlist /tmp/redact-151-export.plist -exportPath /tmp/redact-151-export
xcodebuild -exportArchive -archivePath /tmp/ZeroNetRedact-1.5.1-13.xcarchive -exportOptionsPlist /tmp/redact-151-upload.plist -exportPath /tmp/redact-151-upload
git diff --check
```

结果：ARCHIVE SUCCEEDED、EXPORT SUCCEEDED、Upload succeeded、diff 检查通过。上传日志 `/tmp/redact-151-upload.log`。上传时间约 21:37（上海时区）；Apple 后续处理和审核是独立状态。日志中另一个 Xcode 账户的凭据警告没有阻止本次上传。

实际界面验收：导入 3 页样例 → 搜索 `demo@example.com` → 找到三页各一处 → 应用遮挡 → 检查第二、三页 → 导出。使用 pypdf 对实际输出逐页断言：邮箱无法提取；`PUBLIC-PAGE-1/2/3` 和 `North Studio` 仍可提取；共 3 页。使用 Poppler 渲染复核。此结论仅适用于该测试文件，不保证任意用户文件均已清除全部敏感信息。

## 早期待办（已由构建 14 提交取代）

1. 英文 6.9 英寸截图已上传并核验顺序：PDF 涂黑、文字搜索、导出结果、原有照片、视频、分享。6.5 英寸自动复用该截图组。
2. 新图标已在本地应用，见 `icon/README.md`。构建 13 已可选，显示“缺少出口合规证明”；已取消选择，未送审。若更换图标，需要生成并上传新的构建，再处理出口合规及提交校验。
3. 通过审核后核验公开截图、描述、官网入口和年龄分级，再记录实验 T0。

原生文件选择器问题已解决，三张截图已通过现有 Comet 上传。当前暂停原因：用户要求先完成图标和完整产品定位调整，未授权恢复送审。商店前三张应覆盖照片、视频、PDF；1.5.0 推广文本和 1.5.1 PDF 优先文案也待纠正。

## 本地状态说明

项目原有 Release 自动递增脚本已把下一次构建号设置为 14；归档 Info.plist 核实此次上传仍为 1.5.1（13）。截图时临时设置的 Xcode 英文运行语言已恢复。未提交或推送 Git；已有用户文件变更未覆盖。

## 构建 14 更新

- 新图标已替换，归档版本 1.5.1（14）已核验。
- 英文前三张截图顺序已保存并核验为照片、视频、PDF，其后为 PDF 搜索、PDF 导出、分享。
- 1.5.1 英文推广文本、长描述和中英文更新说明已保存为完整产品定位；1.5.0 英文推广文本同步保存，公开传播待验证。
- 构建命令：`xcodebuild archive -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/ZeroNetRedact-1.5.1-14.xcarchive -derivedDataPath /tmp/redact-151-device CURRENT_PROJECT_VERSION=14`。日志 `/tmp/redact-151-14-archive.log`。
- 上传命令：`xcodebuild -exportArchive -archivePath /tmp/ZeroNetRedact-1.5.1-14.xcarchive -exportOptionsPlist /tmp/redact-151-upload.plist -exportPath /tmp/redact-151-14-upload`。日志 `/tmp/redact-151-14-upload.log`：Upload succeeded / EXPORT SUCCEEDED。
- 归档 dSYM 经 nm 检查包含 MuPDF 的 fz_aes / fz_arc4 实现，出口问卷不可仅依据 Swift CryptoKit 判定。

## 已解决的送审阻碍

App 当前供应 174 个地区，唯一未供应地区为中国大陆，包含法国。构建 14 的实际归档 dSYM 包含 `_fz_aes_crypt_cbc`、`_fz_aes_setkey_enc`、`_fz_arc4_encrypt`，来自 MuPDF。App Store Connect 选择“系统外标准加密算法”及“在法国分发：是”后，明确要求在 App 信息上传出口合规文稿并等待批准。没有选择与实际构建不符的“以上均不属于”，也未修改销售范围。

官方参考：https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption

## 最终提交结果

用户授权取消法国销售后，通过现有 Comet 保存了供应范围更改。构建 14 问卷选择“系统外标准加密算法”和“在法国分发：否”，保存后缺少出口合规提示消失。随后添加以供审核，并点击“提交以供审核”，页面确认“已提交 1 个项目”、版本“正在等待审核”。其余地区、价格、免费额度未调整。

本次 `git diff --check` 通过。归档与上传验证见上文。审批结果和法国公开商店传播尚未验证；未提交或推送 Git。
