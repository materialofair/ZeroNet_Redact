import Foundation

enum VoicePreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case anonymousMale
    case anonymousFemale
    case robot
    case mute

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return NSLocalizedString("voice.original", comment: "")
        case .anonymousMale: return NSLocalizedString("voice.male", comment: "")
        case .anonymousFemale: return NSLocalizedString("voice.female", comment: "")
        case .robot: return NSLocalizedString("voice.robot", comment: "")
        case .mute: return NSLocalizedString("voice.mute", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .original: return "waveform"
        case .anonymousMale: return "person.fill"
        case .anonymousFemale: return "person.fill"
        case .robot: return "cpu"
        case .mute: return "speaker.slash.fill"
        }
    }
}
