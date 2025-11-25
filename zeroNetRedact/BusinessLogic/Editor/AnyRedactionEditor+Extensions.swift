import Foundation

extension AnyRedactionEditor {
    var canUndo: Bool {
        _canUndo()
    }

    var canRedo: Bool {
        _canRedo()
    }

    func loadFile() async throws {
        try await _loadFile()
    }

    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        try await _detectSensitiveRegions()
    }

    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        _applyRedaction(region, effect)
    }

    func undo() {
        _undo()
    }

    func redo() {
        _redo()
    }

    func exportRedactedFile() async throws -> Data {
        try await _exportRedactedFile()
    }
}
