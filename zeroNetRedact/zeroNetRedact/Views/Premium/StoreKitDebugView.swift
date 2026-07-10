#if DEBUG

import StoreKit
import SwiftUI

/// StoreKit调试视图 - 用于测试内购功能
struct StoreKitDebugView: View {
    @StateObject private var storeManager = StoreManager.shared
    @State private var debugLog: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("产品信息") {
                    if storeManager.isLoading {
                        HStack {
                            ProgressView()
                            Text("加载中...")
                                .foregroundColor(.secondary)
                        }
                    } else if storeManager.products.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ 未加载到产品")
                                .foregroundColor(.orange)
                            Text("请检查 Products.storekit 配置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(storeManager.products, id: \.id) { product in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName)
                                    .font(.headline)
                                Text("ID: \(product.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("价格: \(product.displayPrice)")
                                    .font(.subheadline)
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Section("购买状态") {
                    HStack {
                        Text("高级版状态")
                        Spacer()
                        if storeManager.isPremium {
                            Label("已购买", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("未购买", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Text("已购买产品: \(storeManager.purchasedProductIDs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("操作") {
                    Button {
                        Task {
                            addLog("📥 重新加载产品...")
                            await storeManager.loadProducts()
                            addLog("✅ 产品加载完成")
                        }
                    } label: {
                        Label("重新加载产品", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task {
                            addLog("🔄 开始恢复购买...")
                            await storeManager.restorePurchases()
                            addLog("✅ 恢复购买完成")
                        }
                    } label: {
                        Label("恢复购买", systemImage: "purchased.circle")
                    }

                    Button {
                        Task {
                            addLog("🔍 检查当前权益...")
                            await storeManager.updatePurchasedProducts()
                            addLog("✅ 权益检查完成")
                        }
                    } label: {
                        Label("检查权益", systemImage: "checkmark.seal")
                    }

                    Button(role: .destructive) {
                        clearPurchaseState()
                    } label: {
                        Label("清除本地购买状态", systemImage: "trash")
                    }
                }

                Section("调试日志") {
                    if debugLog.isEmpty {
                        Text("暂无日志")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(debugLog.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !debugLog.isEmpty {
                        Button("清除日志") {
                            debugLog.removeAll()
                        }
                    }
                }

                Section("StoreKit测试说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 确保在 Xcode Scheme 中配置了 Products.storekit")
                            .font(.caption)
                        Text("2. 运行应用后应该能看到产品信息")
                            .font(.caption)
                        Text("3. 点击购买会弹出 StoreKit 测试对话框")
                            .font(.caption)
                        Text("4. 测试购买不会产生真实费用")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("StoreKit 调试")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("刷新") {
                        Task {
                            await storeManager.loadProducts()
                        }
                    }
                }
            }
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(timestamp)] \(message)")
    }

    private func clearPurchaseState() {
        UserDefaults.standard.removeObject(forKey: "com.zeronet.redact.purchased")
        addLog("🗑️ 已清除本地购买状态")
        addLog("⚠️ 注意: 这不会清除 StoreKit 测试环境的购买记录")
        Task {
            await storeManager.updatePurchasedProducts()
        }
    }
}

#Preview {
    StoreKitDebugView()
}

#endif
