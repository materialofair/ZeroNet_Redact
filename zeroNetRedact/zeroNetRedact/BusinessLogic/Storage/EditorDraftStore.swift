import Foundation
import UIKit

struct DraftEffect: Codable {
    var kind: String
    var amount: Float = 0
    var color: Data? = nil
    var sticker: String? = nil

    init(_ effect: RedactionEffect) throws {
        switch effect {
        case .solidBlack: kind = "black"
        case .mosaic(let size): kind = "mosaic"; amount = Float(size)
        case .blur(let radius): kind = "blur"; amount = radius
        case .rectangle(let value, let opacity):
            kind = "rectangle"; amount = opacity
            color = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        case .faceSticker(let value): kind = "sticker"; sticker = value.rawValue
        }
    }

    func restored() throws -> RedactionEffect {
        guard amount.isFinite else { throw CocoaError(.coderReadCorrupt) }
        switch kind {
        case "black": return .solidBlack
        case "mosaic":
            guard amount >= 2, amount <= 10000 else { throw CocoaError(.coderReadCorrupt) }
            return .mosaic(pixelSize: Int(amount))
        case "blur": return .blur(radius: amount)
        case "rectangle":
            guard let color, let value = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: color) else { throw CocoaError(.coderReadCorrupt) }
            return .rectangle(color: value, opacity: amount)
        case "sticker":
            guard let sticker, let value = FaceRedactionSticker(rawValue: sticker) else { throw CocoaError(.coderReadCorrupt) }
            return .faceSticker(value)
        default: throw CocoaError(.coderReadCorrupt)
        }
    }
}

struct DraftMask: Codable {
    var bounds: CGRect
    var page: Int?
    var effect: DraftEffect
}

struct DraftRecognition: Codable {
    var type: SensitiveType
    var bounds: CGRect
    var confidence: Float
    var page: Int?
    var confirmed: Bool
    var text: String?
    init(_ region: SensitiveRegion) {
        type = region.type; bounds = region.boundingBox; confidence = region.confidence
        page = region.pageIndex; confirmed = region.isConfirmed; text = region.recognizedText
    }
    var region: SensitiveRegion {
        SensitiveRegion(type: type, boundingBox: bounds, confidence: confidence,
                        pageIndex: page, isConfirmed: confirmed, recognizedText: text)
    }
}

struct DraftFaceCandidate: Codable {
    var id: UUID
    var rect: CGRect
    var selected: Bool
}

struct DraftVideoFrame: Codable {
    var seconds: Double
    var rects: [CGRect]
}

struct DraftVideoState: Codable {
    var sticker: String
    var voicePreset: String
    var frames: [DraftVideoFrame]?
    var frameRate: Double
    var faceCount: Int
    var playbackSeconds: Double

    init(sticker: VideoRedactionSticker, voice: VoicePreset, timeline: VideoFaceTimeline?, playbackSeconds: Double) {
        self.sticker = sticker.rawValue
        voicePreset = voice.rawValue
        frames = timeline?.frames.map { DraftVideoFrame(seconds: $0.seconds, rects: $0.normalizedRects) }
        frameRate = timeline?.frameRate ?? 30
        faceCount = timeline?.totalUniqueFaces ?? 0
        self.playbackSeconds = playbackSeconds.isFinite ? max(0, playbackSeconds) : 0
    }
    var timeline: VideoFaceTimeline? {
        frames.map { VideoFaceTimeline(frames: $0.map { VideoFaceFrame(seconds: $0.seconds, normalizedRects: $0.rects) }, frameRate: frameRate, totalUniqueFaces: faceCount) }
    }
}

struct EditorDraft: Codable {
    var version = 1
    var originalID: UUID
    var modifiedAt = Date()
    // Rotation in this editor bakes prior effects into a new base. Only that changed base is saved.
    var replacementImage: Data?
    var replacementScale: Double? = nil
    var masks: [DraftMask]
    var pageIndex: Int
    var recognition: [DraftRecognition]
    var selectedEffect: DraftEffect
    var faceCandidates: [DraftFaceCandidate]? = nil
    var faceSticker: String? = nil
    var videoState: DraftVideoState? = nil

    func validate() throws {
        guard version == 1, pageIndex >= 0,
              replacementScale.map({ $0.isFinite && $0 > 0 && $0 <= 10 }) ?? true else {
            throw CocoaError(.coderReadCorrupt)
        }
        for mask in masks {
            guard [mask.bounds.origin.x, mask.bounds.origin.y, mask.bounds.width, mask.bounds.height].allSatisfy({ $0.isFinite }),
                  mask.bounds.size.width > 0, mask.bounds.size.height > 0,
                  mask.page.map({ $0 >= 0 }) ?? true else { throw CocoaError(.coderReadCorrupt) }
            _ = try mask.effect.restored()
        }
        _ = try selectedEffect.restored()
        if let state = videoState {
            guard VideoRedactionSticker(rawValue: state.sticker) != nil,
                  VoicePreset(rawValue: state.voicePreset) != nil,
                  state.frameRate.isFinite, state.frameRate > 0,
                  state.playbackSeconds.isFinite, state.playbackSeconds >= 0,
                  state.faceCount >= 0 else { throw CocoaError(.coderReadCorrupt) }
            for frame in state.frames ?? [] {
                guard frame.seconds.isFinite, frame.seconds >= 0 else { throw CocoaError(.coderReadCorrupt) }
                for rect in frame.rects {
                    guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
                          rect.width > 0, rect.height > 0 else { throw CocoaError(.coderReadCorrupt) }
                }
            }
        }
    }
}

/// Encrypted sidecars share the original-file key. The lock orders atomic writes and deletion;
/// revoked session tokens prevent a queued autosave from resurrecting a deleted draft.
final class EditorDraftStore {
    static let shared = EditorDraftStore()
    private let directory: URL
    private let lock = NSLock()
    private var generations: [UUID: UUID] = [:]

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EditorDrafts", isDirectory: true)) {
        self.directory = directory
    }
    func beginSession(for id: UUID) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID(); generations[id] = token; return token
    }
    func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".draft") }
    func load(id: UUID) throws -> EditorDraft? {
        lock.lock(); defer { lock.unlock() }
        let path = url(for: id)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let draft = try JSONDecoder().decode(EditorDraft.self, from: CryptoEngine.shared.decrypt(data: Data(contentsOf: path)))
        guard draft.version == 1, draft.originalID == id else { throw CocoaError(.coderReadCorrupt) }
        try draft.validate()
        return draft
    }
    func save(_ draft: EditorDraft, session: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard generations[draft.originalID] == session else { return }
        try draft.validate()
        let encrypted = try CryptoEngine.shared.encrypt(data: JSONEncoder().encode(draft))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encrypted.write(to: url(for: draft.originalID), options: [.atomic, .completeFileProtection])
    }
    func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        generations[id] = nil
        let path = url(for: id)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}
