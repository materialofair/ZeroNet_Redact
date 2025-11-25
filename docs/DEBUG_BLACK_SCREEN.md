# 黑屏问题调试指南

## 🔍 问题：还是黑屏

即使添加了所有修复，第一次打开图片时还是黑屏。

## 💡 最新修复

### 关键问题：视图初始状态

**根本原因**：
- `viewModel.isLoading` 初始值是 `false`
- `.task {}` 在视图首次渲染**之后**才执行
- 视图渲染时进入 `else` 分支（currentImage == nil）
- 但 `else` 分支没有明确的白色背景（之前修复漏掉了）

**解决方案**：
添加 `@State private var isInitialLoad = true` 追踪初次加载状态

### 修复代码

```swift
struct SimpleBrushEditor: View {
    // 新增
    @State private var isInitialLoad = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack {
                        Color.white  // ✅ 白色底层
                        Color.black.opacity(0.05)  // 浅灰色
                        
                        // ✅ 关键修改：isInitialLoad || viewModel.isLoading
                        if isInitialLoad || viewModel.isLoading {
                            // 加载状态
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.blue)
                                Text("正在解密图片...")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                        } else if let image = viewModel.currentImage {
                            // 图片已加载
                            imageCanvas(image: image, geometry: geometry)
                        } else {
                            // 加载失败
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text("图片加载失败")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                        }
                    }
                }
            }
            .task {
                print("🔵 SimpleBrushEditor: .task 开始执行")
                await viewModel.loadFile()
                isInitialLoad = false  // ✅ 加载完成后设置为false
                print("🔵 SimpleBrushEditor: .task 执行完成")
            }
            .background(Color.white)  // ✅ 整个视图白色背景
        }
        .navigationViewStyle(.stack)  // ✅ 使用stack样式
    }
}
```

## 🧪 测试步骤

### 1. 查看控制台日志

点击图片后，应该**立即**看到：
```
🔵 SimpleBrushEditor: .task 开始执行
```

然后看到加载流程：
```
🔄 EditorViewModel: 开始加载文件...
🔄 EditorViewModel: 正在调用 editor.loadFile()...
🔍 ImageRedactionEditor: 开始加载文件 ID=xxx
✅ 成功读取加密数据，大小: 1234567 bytes
✅ 成功解密数据，大小: 1234567 bytes
✅ 成功创建UIImage，尺寸: (1920.0, 1080.0)
✅ ImageRedactionEditor: 图片已在主线程更新
🔄 EditorViewModel: loadFile() 完成，正在获取图片...
✅ EditorViewModel: 图片已加载，尺寸: (1920.0, 1080.0)
```

最后：
```
🔵 SimpleBrushEditor: .task 执行完成，isInitialLoad = false
```

### 2. 视图渲染检查

**时间线**：

| 时刻 | isInitialLoad | viewModel.isLoading | currentImage | 显示内容 |
|------|---------------|---------------------|--------------|----------|
| 0ms（视图创建） | true | false | nil | ✅ 加载动画 |
| 0ms（.task开始） | true | true | nil | ✅ 加载动画 |
| 100ms-3s（解密中） | true | true | nil | ✅ 加载动画 |
| 3s（加载完成） | false | false | UIImage | ✅ 图片显示 |

**关键点**：
- ✅ 任何时刻都不应该是黑屏
- ✅ 0ms 开始就应该显示白色背景和加载动画

### 3. 如果还是黑屏

**可能原因1**: NavigationView 默认样式问题

**检查方法**：
```swift
// 添加到 NavigationView 后面
.navigationViewStyle(.stack)
```

**可能原因2**: iOS版本或设备特定问题

**检查方法**：
- 在真机上测试
- 在不同的模拟器上测试（iPhone 15, iPhone SE等）

**可能原因3**: 暗黑模式影响

**检查方法**：
```swift
// 添加到 NavigationView 后面
.preferredColorScheme(.light)  // 强制浅色模式
```

**可能原因4**: ZStack 层级问题

**检查方法**：
在 SimpleBrushEditor.swift:77 添加日志：
```swift
if isInitialLoad || viewModel.isLoading {
    print("🟢 显示加载状态: isInitialLoad=\(isInitialLoad), isLoading=\(viewModel.isLoading)")
    VStack(spacing: 16) {
        // ...
    }
}
```

然后检查控制台是否打印了这行日志。

## 🔧 终极调试方案

如果上述方法都不行，添加这个最暴力的测试：

```swift
var body: some View {
    // 暴力测试：直接返回白色背景
    ZStack {
        Color.white.ignoresSafeArea()
        
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(2.0)
                .tint(.red)  // 红色，容易看到
            Text("加载中...")
                .font(.title)
                .foregroundColor(.black)
        }
    }
}
```

**如果这个还是黑屏**，那问题不在我们的代码，而是：
1. Xcode 构建缓存问题 → 清理构建（Shift+Cmd+K）
2. App 缓存问题 → 删除App重新安装
3. 模拟器问题 → 重置模拟器

## ⚡ 快速修复检查清单

- [ ] 确认 SimpleBrushEditor.swift 有 `@State private var isInitialLoad = true`
- [ ] 确认条件是 `if isInitialLoad || viewModel.isLoading`
- [ ] 确认 `.task` 中有 `isInitialLoad = false`
- [ ] 确认有 `.background(Color.white)`
- [ ] 确认有 `.navigationViewStyle(.stack)`
- [ ] 清理构建缓存（Shift+Cmd+K）
- [ ] 重新运行App
- [ ] 查看控制台日志

## 📊 预期结果

**修复成功的标志**：

1. ✅ 点击图片后，**0秒**就看到白色背景
2. ✅ 立即看到蓝色ProgressView（红色用于测试）
3. ✅ 看到"正在解密图片..."文字
4. ✅ 控制台显示完整的加载流程
5. ✅ 1-3秒后图片流畅显示

**如果还有问题**：
- 截图黑屏的样子
- 复制完整的控制台日志
- 说明iOS版本和设备型号
