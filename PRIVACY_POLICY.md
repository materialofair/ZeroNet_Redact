# Cloakmark Privacy Policy / 隐私政策

Last updated / 最后更新：2026-10-24

Cloakmark, listed as **Video Blur: Cloakmark** (formerly ZeroNet Redact), processes photos, videos and PDFs on your device. This policy describes the source in this repository; it is not an independent privacy audit or proof that a store binary matches this source.

Cloakmark 的商店名称为 **Video Blur: Cloakmark**（原 ZeroNet Redact），在设备上处理照片、视频和 PDF。本说明对应本仓库源码，不代表独立隐私审计，也不证明商店二进制与源码完全一致。

## English

### Processing and network use

Media recognition, redaction, video face analysis and voice effects run locally. Processing does not require uploading your original media to a server. No app account is required. The reviewed source does not include developer-operated media upload, advertising, analytics or remote crash-reporting services.

The app **can use the network** through Apple StoreKit. `StoreManager` requests product information at initialization (`Product.products`), handles purchases (`product.purchase`), listens for transaction updates and restores purchases (`AppStore.sync`). Apple may process account, transaction and service data under its own policies. Product queries can occur without you pressing Buy. Offline media processing does not mean that the app never connects to the internet.

Opening external links or choosing a destination in the system share sheet uses the selected website, app or service and its privacy practices. Apple platform diagnostics, Photos, Files providers and device backup/synchronization settings are outside the app's local processing promise.

### Local storage and exported copies

- Imported originals and editing drafts are encrypted locally using the app's CryptoKit storage paths; keys are held in Keychain. Video originals use authenticated chunk encryption.
- Drafts can contain editing operations, recognition results, video settings and rotated replacement images needed for restoration.
- The share extension encrypts incoming images/PDFs in an App Group inbox using a separate key. The containing app consumes the inbox after authentication. Successfully imported entries are removed; failed entries remain encrypted for retry.
- Exported redacted copies are stored **unencrypted** for preview and sharing. Processing can also create temporary decrypted files or decoded data. Encryption of originals does not encrypt every copy or every processing buffer.
- You can delete files managed by the app. Copies saved to Photos, Files, backups or other apps must be managed in those destinations; deleting the app does not remove all such copies. Keychain has its own lifecycle.

### Detection and security limits

`VideoFaceAnalyzer` uses Apple's Vision face rectangle detection with adaptive sampling and `FaceTrackSmoother` to build local face trajectories. `VideoCompositionFactory` renders automatic face covers first, then active manual regions. Manual rectangles stay at the chosen position during their time interval; they do not become motion tracking. Track association and user-confirmed grouping are not identity recognition.

Detection can miss faces or other private details, especially during rapid motion, occlusion or sparse sampling. Blur, stickers, voice effects and encryption do not guarantee anonymity or eliminate privacy risk. Review the entire exported file, including audio and all pages/frames relevant to your material, before sharing. Device access, software defects, temporary files, backups and the destinations you choose can affect privacy.

### Contact and changes

Policy updates are recorded by the date above. For questions, use [GitHub Issues](https://github.com/materialofair/ZeroNet_Redact/issues). Issues are public; do not attach private originals, credentials or sensitive examples.

## 中文

### 处理与联网

媒体识别、脱敏、视频人脸分析和声音效果均在本地运行，处理无需将原始素材上传到服务器，也无需注册应用账号。此次审查的源码未包含开发者运营的媒体上传、广告、使用分析或远程崩溃上报服务。

应用**可以通过 Apple StoreKit 联网**。`StoreManager` 初始化时查询商品信息（`Product.products`），并处理购买（`product.purchase`）、交易更新与恢复购买（`AppStore.sync`）。Apple 可依其自身政策处理账号、交易和服务数据；未点击购买也可能触发商品查询。本地媒体处理不等于应用从不联网。

打开外部链接或在系统分享面板选择目的地，会使用所选网站、应用或服务及其隐私规则。Apple 平台诊断、照片、文件提供程序以及设备备份/同步设置，不属于应用本地处理承诺的范围。

### 本地存储与导出副本

- 导入的原件和编辑草稿通过应用的 CryptoKit 存储路径在本地加密，密钥存于 Keychain；视频原件使用认证分块加密。
- 草稿可能包含编辑操作、识别结果、视频设置和恢复所需的旋转替换图片。
- 分享扩展使用独立密钥，将图片/PDF 加密保存在 App Group 收件箱，主应用通过认证后导入。成功条目删除，失败条目保留为加密内容以便重试。
- 导出的脱敏副本以**未加密形式**保存在本地，便于预览和分享。处理过程也可能产生临时解密文件或解码数据。原件加密不表示所有副本及处理缓冲区均已加密。
- 可删除应用管理的文件；保存到照片、文件、备份或其他应用的副本需在相应目的地管理。卸载应用不会删除所有这些副本，Keychain 也有自身的存续规则。

### 检测与安全限制

`VideoFaceAnalyzer` 通过 Apple Vision 人脸矩形检测、自适应采样与 `FaceTrackSmoother` 生成本地人脸轨迹。`VideoCompositionFactory` 先渲染自动人脸覆盖，再叠加当前时段的手动区域。手动矩形在指定时段保持选定位置，不会因此自动跟随运动；轨迹关联和用户确认的分组不等于身份识别。

检测可能遗漏人脸或其他隐私信息，快速移动、遮挡和稀疏采样等情况尤其需要复核。模糊、贴纸、声音效果和加密均不能保证匿名或消除隐私风险。分享前请检查完整导出文件，包括音频及相关页面/帧。设备访问、软件缺陷、临时文件、备份和所选分享目的地都可能影响隐私。

### 联系与变更

政策更新以顶部日期记录。如有问题，请使用 [GitHub Issues](https://github.com/materialofair/ZeroNet_Redact/issues)。Issues 为公开内容，请勿附上私人原件、凭据或敏感示例。
