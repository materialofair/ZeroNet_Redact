//
//  ImageCache.swift
//  ZeroNet Redact
//
//  图片内存缓存管理器
//

import UIKit

/// 图片缓存管理器（单例）
class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // 设置缓存限制
        cache.countLimit = 50  // 最多缓存50张图片
        cache.totalCostLimit = 100 * 1024 * 1024  // 最多100MB

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// 获取缓存的图片
    func getImage(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    /// 缓存图片
    func setImage(_ image: UIImage, forKey key: String) {
        // 计算图片大小作为cost
        let cost = image.size.width * image.size.height * image.scale * image.scale
        cache.setObject(image, forKey: key as NSString, cost: Int(cost))
    }

    /// 移除指定缓存
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// 清空所有缓存
    @objc func clearCache() {
        cache.removeAllObjects()
        print("🧹 ImageCache: 已清空所有缓存")
    }
}
