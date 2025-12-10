# StoreKit 配置指南

## 📋 Xcode 项目配置步骤

### 1. 添加 Products.storekit 到项目

1. 打开 Xcode 项目
2. 在项目导航器中，右键点击 `zeroNetRedact` 文件夹
3. 选择 "Add Files to zeroNetRedact..."
4. 找到并选择 `Products.storekit` 文件
5. 确保勾选 "Copy items if needed" 和正确的 target
6. 点击 "Add"

### 2. 配置 StoreKit Testing

1. 在 Xcode 中，点击顶部菜单 **Product** → **Scheme** → **Edit Scheme...**
2. 在左侧选择 **Run**
3. 切换到 **Options** 标签页
4. 在 **StoreKit Configuration** 下拉菜单中选择 **Products.storekit**
5. 点击 **Close**

### 3. 验证配置

在 Xcode 中运行项目：
- 应该能看到产品价格显示为 $3.99
- 点击购买按钮会弹出测试购买对话框
- 测试购买不会产生真实费用

## 🧪 本地测试流程

### 测试购买流程

1. **启动应用**：在模拟器或真机上运行
2. **打开Premium页面**：点击设置中的"解锁高级版"
3. **查看产品**：应该显示 "Premium - Lifetime" 产品和价格
4. **测试购买**：
   - 点击购买按钮
   - StoreKit测试环境会弹出确认对话框
   - 选择 "Buy" 完成测试购买
   - 应该看到成功提示

### 测试恢复购买

1. **模拟已购买状态**：完成上述测试购买
2. **清除本地状态**：
   - 删除应用重新安装，或
   - 在 Xcode 中 Product → Scheme → Edit Scheme → Options → StoreKit Configuration → Editor → Clear All Transactions
3. **恢复购买**：
   - 打开Premium页面
   - 点击"恢复购买"
   - 应该成功恢复已购买状态

## 🔍 调试技巧

### 查看StoreKit日志

在 Xcode 控制台中搜索关键词：
- `StoreManager:` - 查看内购管理器日志
- `✅` - 查看成功操作
- `❌` - 查看错误信息

### 常见问题排查

**问题1: 产品加载失败**
- 检查 Products.storekit 是否正确添加到项目
- 检查 Scheme 配置中是否选择了 Products.storekit
- 重新运行项目

**问题2: 购买按钮无响应**
- 查看控制台日志
- 确认产品ID匹配：`com.zeronet.redact.premium`

**问题3: 恢复购买无效**
- 确保之前完成过测试购买
- 检查 StoreKit Configuration → Editor 中的交易记录

## 📱 真机测试准备

### App Store Connect 配置（上架前）

1. **创建内购产品**：
   - 登录 App Store Connect
   - 选择你的应用
   - 进入 "功能" → "App 内购买项目"
   - 点击 "+" 创建新产品
   - 产品ID: `com.zeronet.redact.premium`
   - 类型: 非消耗型项目
   - 价格: $3.99 (或其他定价)

2. **添加测试账号**：
   - App Store Connect → 用户和访问 → 沙盒测试员
   - 创建测试账号用于真机测试

### 真机测试流程

1. **退出App Store账号**：设置 → App Store → 退出登录
2. **运行应用**：从Xcode安装到真机
3. **测试购买**：首次购买时会要求登录，使用沙盒测试账号
4. **验证功能**：完成购买后检查功能解锁

## ✅ 配置检查清单

- [ ] Products.storekit 文件已添加到项目
- [ ] Scheme 中已选择 Products.storekit
- [ ] 产品ID正确：`com.zeronet.redact.premium`
- [ ] StoreManager 代码正确
- [ ] 本地测试购买成功
- [ ] 本地测试恢复购买成功
- [ ] 控制台日志正常

## 🚀 下一步

配置完成后：
1. 在模拟器/真机上测试所有内购流程
2. 验证购买状态持久化
3. 测试网络异常情况
4. 准备App Store Connect配置（上架前）
