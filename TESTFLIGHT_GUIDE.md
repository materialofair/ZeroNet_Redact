# TestFlight 打包上传完整指南

## 📋 前置准备清单

- [ ] Apple Developer 账号（已付费 $99/年）
- [ ] Xcode 已登录 Apple ID
- [ ] 开发者证书已配置
- [ ] App 已在 App Store Connect 创建

---

## 1️⃣ 在 App Store Connect 创建应用

### 步骤 1.1: 登录 App Store Connect
1. 访问 https://appstoreconnect.apple.com
2. 使用你的 Apple Developer 账号登录

### 步骤 1.2: 创建新应用
1. 点击 **"我的 App"**
2. 点击左上角 **"+"** 按钮，选择 **"新建 App"**
3. 填写应用信息：
   - **平台**: iOS
   - **名称**: ZeroNet Redact
   - **主要语言**: 简体中文
   - **套装 ID**: `zeronet.zeroNetRedact`（选择或创建）
   - **SKU**: `zeronet-redact-001`（唯一标识符，自定义）
   - **用户访问权限**: 完全访问权限

4. 点击 **"创建"**

---

## 2️⃣ 配置 Xcode 证书和签名

### 步骤 2.1: 登录 Xcode
1. 打开 Xcode
2. 菜单栏 **Xcode → Settings (Preferences)**
3. 选择 **Accounts** 标签
4. 点击 **"+"** → 选择 **Apple ID**
5. 登录你的 Apple Developer 账号

### 步骤 2.2: 下载证书和配置文件
1. 选择你的账号
2. 点击 **"Manage Certificates"**
3. 点击 **"+"** → 选择 **"Apple Distribution"**
4. 证书会自动下载并安装

### 步骤 2.3: 配置项目签名
1. 打开 Xcode 项目
2. 选择项目根节点（蓝色图标）
3. 选择 **TARGETS → zeroNetRedact**
4. 选择 **Signing & Capabilities** 标签
5. 配置 **Release** 模式：
   - ✅ **Automatically manage signing**（自动管理签名）
   - **Team**: 选择你的开发者团队
   - **Bundle Identifier**: `zeronet.zeroNetRedact`
   - **Provisioning Profile**: Xcode Managed Profile（自动）

---

## 3️⃣ 检查项目配置

### 步骤 3.1: 设置版本号
1. 选择 **TARGETS → zeroNetRedact**
2. 选择 **General** 标签
3. 设置版本信息：
   - **Version**: `1.0`（对外显示版本）
   - **Build**: `1`（内部构建号，每次提交需递增）

### 步骤 3.2: 配置部署目标
- **Deployment Target**: iOS 16.0（最低支持版本）
- 确保与你的 App 需求匹配

### 步骤 3.3: 检查 Info.plist
确保包含必要的权限说明：
- Privacy - Photo Library Usage Description
- Privacy - Camera Usage Description（如需要）
- 其他需要的权限描述

---

## 4️⃣ Archive 打包

### 步骤 4.1: 选择目标设备
1. Xcode 顶部工具栏，选择设备下拉菜单
2. 选择 **"Any iOS Device (arm64)"**
   - ⚠️ 不要选择模拟器，否则无法 Archive

### 步骤 4.2: 执行 Archive
1. 菜单栏 **Product → Archive**
2. 等待编译和打包完成（5-10分钟）
3. 编译成功后会自动打开 **Organizer** 窗口

---

## 5️⃣ 上传到 App Store Connect

### 步骤 5.1: 验证 Archive
在 Organizer 窗口：
1. 选择刚才打包的 Archive
2. 点击右侧 **"Validate App"** 按钮
3. 选择配置：
   - **App Store Connect**: 选择你的账号
   - **Automatically manage signing**（推荐）
4. 点击 **"Validate"**
5. 等待验证完成，确保没有错误

### 步骤 5.2: 分发到 TestFlight
验证成功后：
1. 点击 **"Distribute App"** 按钮
2. 选择 **"App Store Connect"**
3. 点击 **"Next"**
4. 选择 **"Upload"**（上传）
5. 配置选项（保持默认即可）：
   - ✅ Upload your app's symbols
   - ✅ Manage Version and Build Number
6. 选择 **"Automatically manage signing"**
7. 点击 **"Upload"**
8. 等待上传完成（10-20分钟，取决于网络）

### 步骤 5.3: 确认上传成功
上传完成后：
- Xcode 会显示成功消息
- 你会收到 Apple 的邮件通知
- 可以在 App Store Connect 查看构建版本

---

## 6️⃣ 配置 TestFlight

### 步骤 6.1: 等待处理
1. 登录 https://appstoreconnect.apple.com
2. 进入 **"我的 App" → ZeroNet Redact**
3. 选择 **TestFlight** 标签
4. 等待构建版本处理完成（20-60分钟）
   - 状态：正在处理 → 可供测试

### 步骤 6.2: 配置测试信息
构建版本就绪后：
1. 点击构建版本号（如 `1.0 (1)`）
2. 填写 **"测试信息"**：
   - **此版本有什么新功能**: 描述新功能或修复
   - 示例：`首次 TestFlight 测试版本`

3. 填写 **"出口合规信息"**：
   - 如果你的 App 使用加密（HTTPS 也算）：
     - 是否使用加密：**是**
     - 是否使用豁免加密：**是**（如果只用 HTTPS）
     - 添加 `ITSAppUsesNonExemptEncryption = NO` 到 Info.plist（如果适用）

### 步骤 6.3: 添加测试员
1. 选择 **"内部测试"** 或 **"外部测试"**

**内部测试**（最多 100 人，团队成员）：
- 点击 **"+"** 添加测试员
- 选择团队成员
- 测试员会立即收到邮件邀请

**外部测试**（最多 10,000 人，需审核）：
- 点击 **"外部测试"** 标签
- 创建测试组
- 添加测试员邮箱
- 提交审核（Apple 会在 24-48 小时内审核）

---

## 7️⃣ 测试员安装 App

### 步骤 7.1: 测试员接受邀请
1. 测试员收到邮件邀请
2. 点击邮件中的 **"View in TestFlight"**
3. 在 App Store 下载 **TestFlight** App
4. 登录 Apple ID，接受邀请

### 步骤 7.2: 安装测试版本
1. 在 TestFlight App 中查看 **ZeroNet Redact**
2. 点击 **"安装"**
3. 测试并提供反馈

---

## 8️⃣ 后续更新流程

### 更新版本步骤：
1. **递增 Build 号**：
   - Xcode → TARGETS → General
   - Build: `1` → `2` → `3` ...
   - 同一版本号（如 1.0）可以有多个 Build

2. **重复打包上传**：
   - Product → Archive
   - Distribute App
   - 上传到 App Store Connect

3. **自动推送给测试员**：
   - 新构建版本处理完成后
   - TestFlight 会自动通知测试员更新

---

## ⚠️ 常见问题解决

### 问题 1: "No signing certificate found"
**解决方法**：
1. Xcode → Settings → Accounts
2. 选择账号 → Manage Certificates
3. 点击 **"+"** 创建 **Apple Distribution** 证书

### 问题 2: Archive 按钮灰色不可点击
**解决方法**：
1. 确保选择 **"Any iOS Device"** 而不是模拟器
2. 确保 Scheme 设置为 **Release** 模式

### 问题 3: Upload 时提示 "Invalid Bundle"
**解决方法**：
1. 检查 Bundle Identifier 是否与 App Store Connect 一致
2. 检查 Version 和 Build 号是否正确
3. 确保 Info.plist 配置完整

### 问题 4: 构建版本一直"正在处理"
**解决方法**：
- 正常现象，通常需要 20-60 分钟
- 如果超过 2 小时，检查邮件是否有错误通知

### 问题 5: 出口合规问题
**解决方法**：
在 Info.plist 添加：
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
如果只使用 HTTPS 而非自定义加密

---

## 📝 检查清单（每次上传前）

- [ ] 代码已提交到 Git
- [ ] 版本号已更新（Version 或 Build）
- [ ] 选择 "Any iOS Device (arm64)"
- [ ] 执行 Archive
- [ ] Validate App 通过
- [ ] 上传到 App Store Connect
- [ ] 配置 TestFlight 测试信息
- [ ] 添加测试员

---

## 🎯 首次上传快速步骤

如果你是第一次上传，最简化流程：

1. **Xcode 配置**：
   - Settings → Accounts → 登录 Apple ID
   - 项目签名选择 "Automatically manage signing"

2. **App Store Connect 创建 App**：
   - 创建应用，填写基本信息

3. **打包上传**：
   ```
   选择 "Any iOS Device" → Product → Archive → Distribute App → Upload
   ```

4. **配置 TestFlight**：
   - 等待处理完成 → 添加测试员 → 开始测试

---

## 🔗 相关链接

- [App Store Connect](https://appstoreconnect.apple.com)
- [TestFlight 测试指南](https://developer.apple.com/testflight/)
- [Apple Developer 文档](https://developer.apple.com/documentation/)

---

**当前项目信息**：
- Bundle ID: `zeronet.zeroNetRedact`
- Version: `1.0`
- Build: `1`

**准备好了就开始打包吧！🚀**
