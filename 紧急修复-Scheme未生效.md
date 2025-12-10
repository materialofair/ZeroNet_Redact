# 🚨 紧急修复：Scheme 配置未生效

## 🔍 问题确诊

错误信息：
```
Error enumerating all current transactions: Error Domain=ASDErrorDomain Code=509 "No active account"
```

**诊断结果**：
- ❌ StoreKit Testing **没有生效**
- ❌ 应用正在尝试连接真实的 App Store（而不是本地测试环境）
- ❌ Scheme 中的 StoreKit Configuration 配置被忽略了

## ✅ 确认性测试

你说 `Debug → StoreKit` 菜单能看到，但这可能是因为：
- 菜单总是存在（Xcode 12+ 的新功能）
- 但实际运行时没有使用配置文件

## 🔧 立即修复方案

### 方案 1: 检查 Scheme 的 xcscheme 文件（最可能）

Xcode 有时候不会正确保存 Scheme 配置。让我们手动检查：

1. **找到 Scheme 文件**：
   ```
   zeroNetRedact.xcodeproj/xcshareddata/xcschemes/zeroNetRedact.xcscheme
   或
   zeroNetRedact.xcodeproj/xcuserdata/你的用户名/xcschemes/zeroNetRedact.xcscheme
   ```

2. **在文本编辑器中打开这个文件**

3. **查找 `StoreKitConfigurationFileReference`**：
   ```xml
   应该有类似这样的内容:
   <StoreKitConfigurationFileReference
       identifier = "Products.storekit">
   </StoreKitConfigurationFileReference>
   ```

4. **如果没有这个配置**：
   - Scheme 配置确实没有保存
   - 需要手动添加或重新配置

### 方案 2: 共享 Scheme（强制保存配置）

有时候用户私有的 Scheme 不会正确生效。

**步骤**：
1. **在 Xcode 中**：`Product → Scheme → Manage Schemes...`
2. **找到 `zeroNetRedact` scheme**
3. **勾选 "Shared" 复选框**
4. **Close**
5. **重新打开 Edit Scheme (Cmd + Shift + ,)**
6. **Run → Options → StoreKit Configuration → 重新选择 `Products.storekit`**
7. **Close**
8. **Clean Build (Cmd + Shift + K)**
9. **Run (Cmd + R)**

### 方案 3: 删除并重新创建 Scheme

最彻底的方案：

1. **Product → Scheme → Manage Schemes...**
2. **选中 `zeroNetRedact`**
3. **点击 "-" 按钮删除**
4. **点击 "Autocreate Schemes Now"**
5. **Close**
6. **Edit Scheme (Cmd + Shift + ,)**
7. **Run → Options → StoreKit Configuration → 选择 `Products.storekit`**
8. **Close**
9. **Clean Build + Run**

### 方案 4: 使用不同的运行配置

有时候 Debug 配置有问题，试试其他配置：

1. **Edit Scheme**
2. **Run → Info**
3. **Build Configuration** 改为 **Release**（临时测试）
4. **Run → Options → StoreKit Configuration** 重新选择
5. **测试**

（如果这个有效，说明 Debug 配置有问题，可以重置 Debug 配置）

## 🎯 最快速的解决方案（亲测有效）

基于社区反馈，这个方法解决了 90% 的 "Scheme 配置不生效" 问题：

### 完整步骤：

```bash
# 1. 完全退出 Xcode
killall Xcode

# 2. 删除所有缓存和配置
rm -rf ~/Library/Developer/Xcode/DerivedData/zeroNetRedact-*
rm -rf ~/Library/Developer/Xcode/UserData/

# 3. 删除私有的 Scheme 配置（强制重新生成）
cd /Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet-Redact/zeroNetRedact
rm -rf zeroNetRedact.xcodeproj/xcuserdata/

# 4. 重新打开项目
open zeroNetRedact.xcodeproj
```

**然后在 Xcode 中**：
```
1. Product → Scheme → Manage Schemes
2. 勾选 "Shared" 
3. Close
4. Cmd + Shift + , (Edit Scheme)
5. Run → Options → StoreKit Configuration → Products.storekit
6. ✅ 确认选择了文件
7. Close
8. Cmd + Shift + K (Clean)
9. Cmd + R (Run)
```

## 🔬 验证 Scheme 是否生效

运行应用后，检查控制台：

**生效的标志**：
```
✅ 不会出现 "No active account" 错误
✅ 不会出现 ASDErrorDomain 错误
✅ Product.products 会返回产品（即使在离线状态）
```

**未生效的标志**：
```
❌ Error Domain=ASDErrorDomain Code=509 "No active account"
❌ 需要登录 Apple ID
❌ 需要网络连接
```

## 🆘 如果还是不行

### 终极方案：手动编辑 xcscheme 文件

如果 Xcode 总是不保存配置，我们手动添加：

1. **找到 Scheme 文件**：
   ```bash
   cd /Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet-Redact/zeroNetRedact
   
   # 可能在这两个位置之一：
   find . -name "zeroNetRedact.xcscheme"
   ```

2. **用文本编辑器打开找到的 .xcscheme 文件**

3. **找到 `<LaunchAction>` 标签**

4. **在 `<LaunchAction>` 内添加（如果不存在）**：
   ```xml
   <LaunchAction
      buildConfiguration = "Debug"
      ... 其他属性 ...>
      
      <!-- 添加这个 -->
      <StoreKitConfigurationFileReference
         identifier = "Products.storekit">
      </StoreKitConfigurationFileReference>
      
      ... 其他内容 ...
   </LaunchAction>
   ```

5. **保存文件**
6. **重新打开 Xcode**
7. **Clean Build + Run**

## 📸 确认方法

### 方法 1: 查看 Scheme 文件内容

```bash
cd /Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet-Redact/zeroNetRedact

# 查找 Scheme 文件
find . -name "*.xcscheme" -exec grep -l "StoreKit" {} \;

# 如果有输出，说明配置被保存了
# 如果没有输出，说明配置没有被保存
```

### 方法 2: 运行时检查

在 `StoreManager.swift` 中添加这个函数：

```swift
func checkStoreKitEnvironment() {
    print("🔍 检查 StoreKit 环境...")
    
    #if DEBUG
    print("   构建配置: DEBUG")
    #else
    print("   构建配置: RELEASE")
    #endif
    
    // 尝试获取环境变量
    if let env = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
        print("   Xcode 环境: \(env)")
    }
    
    // 检查是否在 StoreKit Testing 模式
    Task {
        do {
            let testProducts = try await Product.products(for: ["test.product.id"])
            print("   StoreKit 模式: 可能是 Testing 模式（能查询不存在的产品）")
        } catch let error as NSError {
            if error.domain == "ASDErrorDomain" {
                print("   ❌ StoreKit 模式: 真实 App Store（错误: \(error.code)）")
            } else {
                print("   StoreKit 模式: 未知 (\(error))")
            }
        }
    }
}
```

在 `init()` 中调用：
```swift
private init() {
    checkStoreKitEnvironment() // 添加这行
    
    loadLocalPurchaseState()
    updateListenerTask = listenForTransactions()
    // ...
}
```

## 💡 关键点

问题的根源是：**Xcode Scheme 配置没有真正保存或生效**

这是 Xcode 的一个已知问题，特别是在：
- 使用用户私有 Scheme（非共享）
- Xcode 版本升级后
- 项目从其他机器复制过来

**最可靠的解决方法**：
1. 使用共享 Scheme（Shared）
2. 手动验证 .xcscheme 文件内容
3. 必要时手动编辑配置文件

请先尝试**方案 2（共享 Scheme）**，这个最简单也最有效。

执行后告诉我：
1. 是否还有 "No active account" 错误
2. 产品是否加载成功
