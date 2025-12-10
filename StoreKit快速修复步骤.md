# StoreKit 快速修复步骤

## ✅ 好消息

你的配置基本正确！`Debug → StoreKit → Manage Transactions` 能看到说明 StoreKit Testing 已启用。

## 🔧 立即尝试这些步骤

### Step 1: 在 Xcode 中打开 Products.storekit

这一步很重要！

1. **在 Xcode 项目导航器中**，找到 `Products.storekit` 文件
2. **单击打开它**
3. **你应该看到 Xcode 的 StoreKit 编辑器界面**，而不是纯文本
4. **检查产品是否显示**：
   - 应该看到 "Premium Lifetime" 产品
   - 产品ID: com.zeronet.redact.premium
   - 价格: $3.99

如果看到产品，说明文件被正确识别了。

### Step 2: 彻底重启应用

```
1. 停止当前运行的应用 (Cmd + .)
2. Clean Build Folder (Cmd + Shift + K)
3. 等待清理完成
4. 重新运行 (Cmd + R)
```

### Step 3: 如果还是失败，尝试"同步"

在 Xcode 的 StoreKit 编辑器中（打开 Products.storekit 文件后）：

1. 在编辑器窗口中，查看顶部工具栏
2. 找到并点击 **Editor** 菜单
3. 选择 **Sync with App Store Connect** 或类似选项（如果有）
4. 或者直接保存文件: `Cmd + S`

### Step 4: 验证产品配置

在 Xcode 的 StoreKit 编辑器中，确认：

**产品信息**：
- ✅ Reference Name: Premium Lifetime
- ✅ Product ID: com.zeronet.redact.premium
- ✅ Price: $3.99
- ✅ Type: Non-Consumable

**本地化**：
- ✅ English (en_US): "Premium - Lifetime"
- ✅ Chinese Simplified (zh_CN): "高级版 - 终身"

### Step 5: 使用 Xcode 内置测试

不通过应用，直接在 Xcode 中测试：

1. **运行应用**
2. **在 Xcode 菜单**：`Debug → StoreKit → Manage Transactions`
3. **应该能看到测试环境的交易管理器**

如果这个窗口能打开，说明 StoreKit Testing 环境是好的。

### Step 6: 测试最简单的代码

在你的 StoreKitDebugView 或调试界面中，添加这个测试按钮：

```swift
Button("直接测试 API") {
    Task {
        do {
            print("🧪 开始直接测试...")
            let testProducts = try await Product.products(for: ["com.zeronet.redact.premium"])
            print("✅ 测试结果: \(testProducts.count) 个产品")
            if testProducts.isEmpty {
                print("❌ 产品为空 - 可能是配置文件格式问题")
            } else {
                for p in testProducts {
                    print("  - \(p.displayName): \(p.displayPrice)")
                }
            }
        } catch {
            print("❌ 测试失败: \(error)")
        }
    }
}
```

## 🎯 最可能的原因

基于你的情况（StoreKit Testing 已启用但产品为空），最可能的原因是：

### 原因 1: 文件未被 Xcode "编译"

**症状**：虽然文件在项目中，但 Xcode 没有将它作为 StoreKit 配置处理。

**解决方案**：
1. 在 Xcode 中打开 Products.storekit
2. 随便修改点什么（比如价格改成 4.99）
3. 保存（Cmd + S）
4. 改回来（价格改回 3.99）
5. 保存
6. 重新运行

这个操作会强制 Xcode 重新处理这个文件。

### 原因 2: internalID 格式问题

StoreKit Configuration 文件的 `internalID` 字段必须是数字。我已经更新了你的文件。

### 原因 3: 缓存问题

虽然你已经 Clean Build 了，但可能需要更彻底的清理：

```bash
# 1. 关闭 Xcode
# 2. 删除 DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/zeroNetRedact-*

# 3. 重新打开项目
```

## 🔬 高级调试

如果以上都不行，在 StoreManager 中添加更详细的日志：

```swift
func loadProducts() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let productIDs = StoreProduct.allCases.map { $0.rawValue }
        print("🔍 StoreManager: 开始加载产品")
        print("   产品ID列表: \(productIDs)")
        
        // 检查运行环境
        #if DEBUG
        print("   运行环境: DEBUG")
        #else
        print("   运行环境: RELEASE")
        #endif
        
        // 检查是否在模拟器
        #if targetEnvironment(simulator)
        print("   设备类型: 模拟器")
        #else
        print("   设备类型: 真机")
        #endif
        
        products = try await Product.products(for: productIDs)
        
        print("✅ StoreManager: 加载完成")
        print("   返回产品数: \(products.count)")
        
        if products.isEmpty {
            print("⚠️ 产品列表为空 - 可能的原因:")
            print("   1. Products.storekit 文件格式错误")
            print("   2. Scheme 配置未生效")
            print("   3. 产品ID不匹配")
            print("   4. Xcode 缓存问题")
        } else {
            for product in products {
                print("📦 产品详情:")
                print("   ID: \(product.id)")
                print("   显示名称: \(product.displayName)")
                print("   价格: \(product.displayPrice)")
                print("   描述: \(product.description)")
                print("   类型: \(product.type)")
            }
        }
    } catch {
        print("❌ StoreManager: 加载产品失败")
        print("   错误类型: \(type(of: error))")
        print("   错误信息: \(error.localizedDescription)")
        print("   详细错误: \(error)")
        
        errorMessage = String(
            format: NSLocalizedString("store.loadFailed", comment: ""),
            error.localizedDescription)
    }
}
```

## 📋 检查清单

在重新运行之前，确认：

- [ ] Xcode 中打开了 Products.storekit 并看到了 StoreKit 编辑器界面
- [ ] 编辑器中能看到 "Premium Lifetime" 产品
- [ ] Product ID 是 `com.zeronet.redact.premium`
- [ ] Scheme → Run → Options → StoreKit Configuration 选择了 `Products.storekit`
- [ ] 执行了 Clean Build (Cmd + Shift + K)
- [ ] 重新运行了应用 (Cmd + R)
- [ ] Debug → StoreKit → Manage Transactions 能打开

## 🎯 90% 有效的方案

基于社区反馈，这个方案解决了大多数类似问题：

1. **完全退出 Xcode**
2. **删除 Products.storekit 文件**（从 Xcode 和文件系统）
3. **重新打开 Xcode**
4. **通过 Xcode GUI 创建新的 StoreKit Configuration File**：
   - File → New → File
   - 选择 "StoreKit Configuration File"
   - 命名为 "Products"
5. **在 StoreKit 编辑器中手动添加产品**
6. **配置 Scheme**
7. **运行测试**

虽然这看起来很麻烦，但通过 Xcode GUI 创建的文件肯定是正确格式的。

## 💡 立即尝试

现在请：

1. **在 Xcode 中打开 Products.storekit**
2. **看看是否显示为 StoreKit 编辑器**
3. **检查产品是否在那里**
4. **Clean Build + 重新运行**
5. **告诉我结果**

如果还是不行，我们就用方案 "通过 Xcode GUI 重新创建文件"。
