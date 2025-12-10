import SwiftUI

/// 图片操作处理器
/// 负责处理图片相关的所有操作（脱敏区域管理等）
@MainActor
class ImageOperationsHandler {
    private weak var editor: AnyRedactionEditor?

    init(editor: AnyRedactionEditor?) {
        self.editor = editor
    }

    // MARK: - 脱敏区域管理

    /// 获取所有图片脱敏区域
    func getRedactionRegions() -> [(index: Int, bounds: CGRect)] {
        guard let imageEditor = editor?.baseEditor as? ImageRedactionEditor else {
            return []
        }

        return imageEditor.getRedactionRegions()
    }

    /// 查找指定点击位置的脱敏区域
    func findRedactionRegion(at point: CGPoint) -> Int? {
        guard let imageEditor = editor?.baseEditor as? ImageRedactionEditor else {
            return nil
        }

        return imageEditor.findRedactionRegion(at: point)
    }

    /// 移动脱敏区域位置
    func moveRedactionRegion(at index: Int, offset: CGSize) {
        guard let imageEditor = editor?.baseEditor as? ImageRedactionEditor else {
            return
        }

        imageEditor.moveRedactionRegion(at: index, offset: offset)
    }

    /// 移除脱敏区域
    func removeRedactionRegion(at index: Int) {
        guard let imageEditor = editor?.baseEditor as? ImageRedactionEditor else {
            return
        }

        imageEditor.removeRedactionRegion(at: index)
    }

    /// 缩放脱敏区域大小
    func scaleRedactionRegion(at index: Int, scale: CGFloat) {
        guard let imageEditor = editor?.baseEditor as? ImageRedactionEditor else {
            return
        }

        imageEditor.scaleRedactionRegion(at: index, scale: scale)
    }
}
