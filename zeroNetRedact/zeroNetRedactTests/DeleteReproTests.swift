//
//  DeleteReproTests.swift
//  临时复现测试：导入图片后删除是否报错
//

import CoreData
import UIKit
import XCTest

@testable import zeroNetRedact

@MainActor
final class DeleteReproTests: XCTestCase {

    func testImportThenDeleteImageViaViewModel() async throws {
        // 1. 构造一张真实 PNG 图片
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let data = image.pngData()!

        // 2. 走真实导入路径（与 importPhotos 相同的 .imageData 来源）
        let imported = try await ImportManager.shared.importFile(from: .imageData(data))
        print("REPRO: imported id=\(imported.id)")

        // 3. 复刻 attachToSelectedGroup：挂到默认分组
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<OriginalFile>(entityName: "OriginalFile")
        request.predicate = NSPredicate(format: "id == %@", imported.id as CVarArg)
        let entity = try XCTUnwrap(try context.fetch(request).first)
        if let defaultGroup = GroupManager.shared.getDefaultGroup() {
            let moved = GroupManager.shared.moveFile(entity, to: defaultGroup)
            print("REPRO: moved to default group = \(moved)")
        } else {
            print("REPRO: no default group found")
        }

        // 4. 用真实的 ImportViewModel.deleteFile 删除
        let vm = ImportViewModel()
        vm.loadOriginalFiles()
        let target = try XCTUnwrap(vm.originalFiles.first { $0.id == imported.id })
        vm.deleteFile(target)

        print("REPRO: showError=\(vm.showError) errorMessage=\(vm.errorMessage ?? "nil")")
        XCTAssertFalse(vm.showError, "删除报错: \(vm.errorMessage ?? "")")
        XCTAssertNil(vm.originalFiles.first { $0.id == imported.id }, "文件仍在列表中")
    }
}
