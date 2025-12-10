# 在 Xcode 中创建 StoreKit 配置文件

## ⚠️ 重要发现

StoreKit 配置文件（.storekit）**不能手动编写 JSON**，必须通过 Xcode 的图形界面创建。手动创建的 JSON 文件格式不被 Xcode 识别。

## 🛠️ 正确的创建步骤

### 步骤 1: 在 Xcode 中创建 StoreKit 配置文件

1. **打开 Xcode 项目**
   ```
   打开 zeroNetRedact.xcodeproj
   ```

2. **创建新文件**
   - 在项目导航器中，右键点击 `zeroNetRedact` 文件夹
   - 选择 **File → New → File...** (或按 `Cmd + N`)

3. **选择文件类型**
   - 在模板选择器中，选择 **Resource** 分类
   - 找到并选择 **StoreKit Configuration File**
   - 点击 **Next**

4. **命名文件**
   - 文件名输入: `Products`
   - 保存位置: 确保在 `zeroNetRedact/zeroNetRedact/` 文件夹下
   - Target: 勾选 `zeroNetRedact`
   - 点击 **Create**

### 步骤 2: 配置产品信息

创建文件后，Xcode 会自动打开 StoreKit 配置编辑器：

1. **添加产品**
   - 点击左下角的 **"+"** 按钮
   - 选择 **Add Non-Consumable In-App Purchase**

2. **配置产品信息**
   
   **基本信息**：
   - **Reference Name**: `Premium Lifetime`
   - **Product ID**: `com.zeronet.redact.premium`
   - **Price**: `$3.99`

3. **添加本地化信息**
   
   点击 **"Localizations"** 部分的 **"+"**：
   
   **英文 (en_US)**:
   - Display Name: `Premium - Lifetime`
   - Description: `Unlock unlimited image and document processing with lifetime access. No recurring charges, pay once and use forever.`
   
   再次点击 **"+"** 添加中文：
   
   **简体中文 (zh_CN)**:
   - Display Name: `高级版 - 终身`
   - Description: `解锁无限图片和文档处理，终身有效。一次购买，永久使用，无需订阅。`

4. **保存文件**
   - `Cmd + S` 保存

### 步骤 3: 配置 Scheme

1. **打开 Scheme 编辑器**
   - 点击顶部工具栏的 Scheme 下拉菜单
   - 选择 **Edit Scheme...**
   - 或按 `Cmd + Shift + ,`

2. **配置 StoreKit Testing**
   - 左侧选择 **Run**
   - 切换到 **Options** 标签页
   - 找到 **StoreKit Configuration** 下拉菜单
   - 选择 **Products.storekit**
   - 点击 **Close**

### 步骤 4: 测试验证

1. **清理并重新构建**
   - `Cmd + Shift + K` (Clean Build)
   - `Cmd + R` (Run)

2. **打开调试界面**
   - 进入设置页面
   - 连续点击版本号 "v1.0.0" **5次**
   - 应该打开 StoreKit 调试界面

3. **验证产品**
   - 应该看到产品信息：
     - 产品名称: "Premium - Lifetime"
     - 价格: "$3.99"
     - 产品ID: "com.zeronet.redact.premium"

4. **查看控制台日志**
   ```
   🔍 StoreManager: 开始加载产品 - ["com.zeronet.redact.premium"]
   ✅ StoreManager: 加载了 1 个产品
     📦 产品: com.zeronet.redact.premium
        显示名称: Premium - Lifetime
        价格: $3.99
        描述: Unlock unlimited image and document processing...
   ```

## 🎯 完整配置清单

按顺序完成以下步骤：

- [ ] 在 Xcode 中创建 StoreKit Configuration File
- [ ] 命名为 `Products.storekit`
- [ ] 添加 Non-Consumable 产品
- [ ] 设置 Product ID: `com.zeronet.redact.premium`
- [ ] 设置价格: $3.99
- [ ] 添加英文本地化
- [ ] 添加中文本地化
- [ ] 保存文件
- [ ] 配置 Scheme 选择 Products.storekit
- [ ] Clean Build
- [ ] 运行测试
- [ ] 验证产品加载成功

## 📸 界面参考

### StoreKit Configuration 编辑器应该显示：

```
Products.storekit
├── In-App Purchases
│   └── Premium Lifetime
│       ├── Type: Non-Consumable
│       ├── Product ID: com.zeronet.redact.premium
│       ├── Price: $3.99
│       └── Localizations
│           ├── en_US: Premium - Lifetime
│           └── zh_CN: 高级版 - 终身
└── Subscriptions
    (empty)
```

## 🐛 常见问题

### Q1: 找不到 StoreKit Configuration File 模板

**解决方法**:
- 确保 Xcode 版本 ≥ 12.0
- 在文件模板选择器中，使用搜索框搜索 "storekit"
- 如果还是找不到，尝试更新 Xcode

### Q2: 产品加载后仍然是 0

**检查清单**:
1. Scheme 是否配置了 StoreKit Configuration
2. Product ID 是否完全匹配: `com.zeronet.redact.premium`
3. 是否执行了 Clean Build
4. 是否重新启动了应用

### Q3: Scheme 下拉菜单中没有 Products.storekit

**解决方法**:
1. 确认文件已创建并保存
2. 确认 Target Membership 包含 `zeroNetRedact`
3. 重启 Xcode

## 💡 小贴士

1. **StoreKit 配置文件是 Xcode 专有格式**
   - 不是标准的 JSON 或 plist
   - 必须通过 Xcode 图形界面编辑
   - 手动编写的 JSON 文件无法识别

2. **产品 ID 规范**
   - 格式: `com.公司域名.应用名.产品名`
   - 必须与 App Store Connect 中配置的一致
   - 一旦设置不要修改

3. **测试环境**
   - StoreKit Testing 完全在本地运行
   - 不需要网络连接
   - 不会产生真实费用
   - 可以模拟各种购买场景

---

**完成这些步骤后，内购功能应该就能正常工作了！**

如果还有问题，请提供：
1. Xcode 控制台的完整日志
2. Products.storekit 编辑器的截图
3. Scheme 配置的截图
