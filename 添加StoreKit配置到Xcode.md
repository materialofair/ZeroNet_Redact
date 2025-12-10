# 如何添加 Products.storekit 到 Xcode 项目

## 📍 文件位置确认

Products.storekit 文件已经创建在：
```
/Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet-Redact/zeroNetRedact/zeroNetRedact/Products.storekit
```

## 🔧 添加到 Xcode 项目的步骤

### 方法一：通过 Xcode 界面添加（推荐）

1. **打开 Xcode 项目**
   ```
   打开 zeroNetRedact.xcodeproj
   ```

2. **定位到正确的文件夹**
   - 在左侧项目导航器中
   - 找到 `zeroNetRedact` 文件夹（蓝色图标）
   - 这个文件夹应该包含你的 Swift 文件

3. **添加文件**
   - 右键点击 `zeroNetRedact` 文件夹
   - 选择 **"Add Files to 'zeroNetRedact'..."**
   - 在文件选择器中，导航到：
     ```
     zeroNetRedact/zeroNetRedact/Products.storekit
     ```
   - 选中 `Products.storekit` 文件

4. **确认添加选项**
   - ✅ 确保勾选 **"Copy items if needed"**（虽然文件已在项目内）
   - ✅ 确保选中正确的 Target: `zeroNetRedact`
   - ✅ 在 "Add to targets" 中勾选 `zeroNetRedact`
   - 点击 **"Add"**

5. **验证添加成功**
   - 在项目导航器中应该能看到 `Products.storekit` 文件
   - 文件图标应该是 StoreKit 配置文件的图标（类似购物袋）

### 方法二：直接拖拽（简单快速）

1. **打开 Finder 和 Xcode**
   - Finder: 导航到 `zeroNetRedact/zeroNetRedact/` 文件夹
   - Xcode: 打开项目

2. **拖拽文件**
   - 从 Finder 中拖拽 `Products.storekit`
   - 拖到 Xcode 左侧项目导航器的 `zeroNetRedact` 文件夹中

3. **确认添加选项**
   - ✅ 勾选 **"Copy items if needed"**
   - ✅ 确保选中 Target: `zeroNetRedact`
   - 点击 **"Finish"**

## ⚙️ 配置 Scheme 使用 StoreKit Testing

添加文件后，必须配置 Scheme 才能使用：

1. **打开 Scheme 编辑器**
   - 点击顶部工具栏的 Scheme 下拉菜单（通常显示 "zeroNetRedact"）
   - 选择 **"Edit Scheme..."**
   - 或者使用快捷键: `Cmd + Shift + ,`

2. **配置 Run Options**
   - 在左侧选择 **"Run"**
   - 切换到 **"Options"** 标签页
   - 找到 **"StoreKit Configuration"** 部分

3. **选择配置文件**
   - 点击 "StoreKit Configuration" 下拉菜单
   - 应该能看到 **"Products.storekit"** 选项
   - 选择它
   - 点击 **"Close"**

## ✅ 验证配置成功

### 检查1: 文件已添加
- [ ] 在 Xcode 项目导航器中能看到 `Products.storekit`
- [ ] 点击该文件，能在右侧看到 StoreKit 配置界面

### 检查2: Scheme 已配置
- [ ] Edit Scheme → Run → Options → StoreKit Configuration
- [ ] 显示为 "Products.storekit"

### 检查3: 运行测试
1. **运行应用** (`Cmd + R`)
2. **打开设置页面**
3. **点击版本号 5 次** 打开调试界面
4. **检查产品加载**
   - 应该显示 "Premium - Lifetime" 产品
   - 价格显示为 "$3.99"

### 检查4: 控制台日志
在 Xcode 控制台中应该看到：
```
🔍 StoreManager: 开始加载产品 - ["com.zeronet.redact.premium"]
✅ StoreManager: 加载了 1 个产品
  📦 产品: com.zeronet.redact.premium
     显示名称: Premium - Lifetime
     价格: $3.99
     描述: Unlock unlimited image and document processing...
```

## 🐛 故障排查

### 问题1: 找不到 Products.storekit 文件选项

**解决方法**:
```bash
# 确认文件存在
ls -la zeroNetRedact/zeroNetRedact/Products.storekit

# 如果文件不存在，重新创建
# 文件内容见下方
```

### 问题2: Scheme 下拉菜单中没有 Products.storekit

**可能原因**:
- 文件未正确添加到项目
- 文件格式不正确

**解决方法**:
1. 在项目导航器中选中 `Products.storekit`
2. 查看右侧文件检查器 (File Inspector)
3. 确认 Target Membership 中勾选了 `zeroNetRedact`

### 问题3: 产品加载失败

**检查步骤**:
1. 确认 Scheme 已配置
2. 重新运行应用 (Clean Build: `Cmd + Shift + K`，然后 `Cmd + R`)
3. 查看控制台日志

## 📋 Products.storekit 文件内容

如果需要重新创建文件，内容应该是：

```json
{
  "identifier" : "D8F4A2C1",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayPrice" : "3.99",
      "familyShareable" : false,
      "internalID" : "6738492816",
      "localizations" : [
        {
          "description" : "Unlock unlimited image and document processing with lifetime access. No recurring charges, pay once and use forever.",
          "displayName" : "Premium - Lifetime",
          "locale" : "en_US"
        },
        {
          "description" : "解锁无限图片和文档处理，终身有效。一次购买，永久使用，无需订阅。",
          "displayName" : "高级版 - 终身",
          "locale" : "zh_CN"
        }
      ],
      "productID" : "com.zeronet.redact.premium",
      "referenceName" : "Premium Lifetime",
      "type" : "NonConsumable"
    }
  ],
  "settings" : {
    "_failTransactionsEnabled" : false,
    "_locale" : "en_US",
    "_storefront" : "USA",
    "_storeKitErrors" : [
      {
        "current" : null,
        "enabled" : false,
        "name" : "Load Products"
      }
    ]
  },
  "subscriptionGroups" : [],
  "version" : {
    "major" : 3,
    "minor" : 0
  }
}
```

## 🎯 快速操作清单

按顺序执行：

1. [ ] 打开 Xcode 项目
2. [ ] 右键点击 `zeroNetRedact` 文件夹 → "Add Files to..."
3. [ ] 选择 `Products.storekit` 文件
4. [ ] 确认 Target 勾选正确
5. [ ] 点击 "Add"
6. [ ] 打开 Scheme 编辑器 (`Cmd + Shift + ,`)
7. [ ] Run → Options → StoreKit Configuration → 选择 "Products.storekit"
8. [ ] Close
9. [ ] 运行应用测试 (`Cmd + R`)
10. [ ] 打开调试界面验证（设置 → 点击版本号5次）

---

**完成这些步骤后，内购功能应该就能正常工作了！**
