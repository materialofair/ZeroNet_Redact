import Combine
import Foundation
import StoreKit

/// 内购产品ID
enum StoreProduct: String, CaseIterable {
    case premium = "com.zeronet.redact.premium"

    var displayName: String {
        switch self {
        case .premium:
            return NSLocalizedString("store.product.premium.name", comment: "")
        }
    }
}

/// StoreKit 2 内购管理器
@MainActor
class StoreManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StoreManager()

    // MARK: - Published Properties

    /// 产品列表
    @Published private(set) var products: [Product] = []

    /// 购买状态
    @Published private(set) var purchasedProductIDs: Set<String> = []

    /// 是否正在加载
    @Published private(set) var isLoading = false

    /// 错误信息
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    /// 是否已购买高级版
    var isPremium: Bool {
        purchasedProductIDs.contains(StoreProduct.premium.rawValue)
    }

    /// 高级版产品
    var premiumProduct: Product? {
        products.first { $0.id == StoreProduct.premium.rawValue }
    }

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - UserDefaults Keys

    private let purchasedKey = "com.zeronet.redact.purchased"

    // MARK: - Initialization

    private init() {
        // 启动时加载本地购买状态
        loadLocalPurchaseState()

        // 启动交易监听
        updateListenerTask = listenForTransactions()

        // 加载产品
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public Methods

    /// 加载产品信息
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let productIDs = StoreProduct.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)
            print("✅ StoreManager: 加载了 \(products.count) 个产品")
        } catch {
            print("❌ StoreManager: 加载产品失败 - \(error)")
            errorMessage = String(
                format: NSLocalizedString("store.loadFailed", comment: ""),
                error.localizedDescription)
        }
    }

    /// 购买产品
    func purchase(_ product: Product) async throws -> Bool {
        print("🛒 StoreManager: 开始购买 \(product.id)")

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // 验证交易
            let transaction = try checkVerified(verification)

            // 更新购买状态
            await updatePurchasedProducts()

            // 完成交易
            await transaction.finish()

            print("✅ StoreManager: 购买成功 - \(product.id)")
            return true

        case .userCancelled:
            print("⚠️ StoreManager: 用户取消购买")
            return false

        case .pending:
            print("⏳ StoreManager: 购买待处理（需要家长批准等）")
            return false

        @unknown default:
            print("❓ StoreManager: 未知购买结果")
            return false
        }
    }

    /// 恢复购买
    func restorePurchases() async {
        print("🔄 StoreManager: 开始恢复购买")
        isLoading = true
        defer { isLoading = false }

        do {
            // 同步App Store的购买记录
            try await AppStore.sync()

            // 更新购买状态
            await updatePurchasedProducts()

            print("✅ StoreManager: 恢复购买完成")
        } catch {
            print("❌ StoreManager: 恢复购买失败 - \(error)")
            errorMessage = String(
                format: NSLocalizedString("store.restoreFailed", comment: ""),
                error.localizedDescription)
        }
    }

    /// 更新购买状态
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        // 检查所有非消耗型产品的购买状态
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // 非消耗型产品，只要有交易记录就算已购买
                if transaction.productType == .nonConsumable {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("⚠️ StoreManager: 交易验证失败 - \(error)")
            }
        }

        // 更新状态
        self.purchasedProductIDs = purchased

        // 保存到本地
        savePurchaseState()

        // 同步到 AppState
        AppState.shared.isPremium = isPremium

        print("📦 StoreManager: 已购买产品 - \(purchased)")
    }

    // MARK: - Private Methods

    /// 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    // 更新购买状态
                    await self.updatePurchasedProducts()

                    // 完成交易
                    await transaction.finish()
                } catch {
                    print("⚠️ StoreManager: 交易更新处理失败 - \(error)")
                }
            }
        }
    }

    /// 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    /// 保存购买状态到本地
    private func savePurchaseState() {
        UserDefaults.standard.set(isPremium, forKey: purchasedKey)
    }

    /// 从本地加载购买状态
    private func loadLocalPurchaseState() {
        let localPurchased = UserDefaults.standard.bool(forKey: purchasedKey)
        if localPurchased {
            purchasedProductIDs.insert(StoreProduct.premium.rawValue)
        }
    }
}
