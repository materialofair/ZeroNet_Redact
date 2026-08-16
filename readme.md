<div align="center">

# ZeroNet Redact

**完全离线的隐私脱敏工具**

[English](#english) | [中文](#中文)

</div>

---

## 中文

### 为什么做这个应用？

在这个数据被肆意窃取的时代，我们分享一张截图前，总要担心是否暴露了手机号、地址、银行卡号。市面上的「隐私工具」大多需要上传到云端处理——这本身就是一种讽刺。

**ZeroNet Redact 的答案很简单：让你的照片永远不离开你的手机。**

### 核心理念

- **零网络** — 应用完全离线运行，没有网络权限，你的文件永远不会被上传
- **本地处理** — 所有脱敏操作都在你的设备上完成，没有云端、没有服务器
- **隐私至上** — 无账号、无追踪、无广告，我们不知道你是谁，也不想知道
- **开源透明** — 开源不是为了免费，而是为了让你可以验证我们的承诺，建立彼此的信任

### 功能特性

- 手势涂抹马赛克
- 矩形遮挡（黑条/白条）
- 高斯模糊
- 撤销/重做
- 加密存储原图
- 视频逐帧人脸检测，支持强模糊与卡通贴纸遮挡
- 固定匿名男声、匿名女声、机器人和静音预设
- 视频原件认证分块加密，处理与换声完全离线
- 导出到相册或分享

### 系统要求

- iOS 17.0+
- iPhone / iPad

### 安装

从 [App Store](#) 下载（即将上线）

或克隆代码自行编译：

```bash
git clone https://github.com/materialofair/ZeroNet-Redact.git
cd ZeroNet-Redact/zeroNetRedact
open zeroNetRedact.xcodeproj
```

### 隐私政策

**我们的承诺：不收集任何数据。**

- 所有图片、PDF 和视频处理都在本地完成
- 加密文件仅存储在你的设备上
- 我们不会上传任何图片或数据
- 我们不会追踪你的使用行为

### 反馈与建议

如果你有任何问题或建议，欢迎通过 [GitHub Issues](https://github.com/materialofair/ZeroNet-Redact/issues) 与我们联系。

### 许可证

[GPL-3.0 License](LICENSE)

App 自身代码以 GPL-3.0 许可；二进制链接 MuPDF（AGPL-3.0）后按 AGPL-3.0
分发（GPLv3 §13），详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## English

### Why This App?

In an era where data is stolen at will, we worry about exposing phone numbers, addresses, or bank details before sharing a screenshot. Most "privacy tools" require uploading to the cloud—which is ironic in itself.

**ZeroNet Redact's answer is simple: your photos never leave your device.**

### Core Philosophy

- **Zero Network** — The app runs completely offline with no network permissions. Your files never get uploaded.
- **Local Processing** — All redaction happens on your device. No cloud, no servers.
- **Privacy First** — No accounts, no tracking, no ads. We don't know who you are, and we don't want to.
- **Open Source** — Open source isn't about being free—it's about letting you verify our promises and building mutual trust.

### Features

- Gesture-based mosaic drawing
- Rectangle masking (black/white bars)
- Gaussian blur
- Undo/Redo
- Encrypted storage for originals
- Frame-by-frame video face detection with strong blur or cartoon sticker covering
- Fixed anonymous male, anonymous female, robot, and mute voice presets
- Authenticated chunk encryption for source videos; processing and voice effects stay offline
- Export to Photos or Share

### Requirements

- iOS 17.0+
- iPhone / iPad

### Installation

Download from [App Store](#) (Coming Soon)

Or clone and build:

```bash
git clone https://github.com/materialofair/ZeroNet-Redact.git
cd ZeroNet-Redact/zeroNetRedact
open zeroNetRedact.xcodeproj
```

### Privacy Policy

**Our Promise: We collect nothing.**

- All image, PDF, and video processing happens locally
- Encrypted files are stored only on your device
- We never upload any images or data
- We never track your usage

### Feedback

If you have any questions or suggestions, feel free to reach out via [GitHub Issues](https://github.com/materialofair/ZeroNet-Redact/issues).

### License

[GPL-3.0 License](LICENSE)

The app's own source code is GPL-3.0; the distributed binary links MuPDF
(AGPL-3.0) and is therefore distributed under AGPL-3.0 (GPLv3 §13). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

<div align="center">

Made with privacy in mind.

</div>
