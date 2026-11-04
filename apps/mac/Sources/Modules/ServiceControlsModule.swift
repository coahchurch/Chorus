import SwiftUI

enum ServiceControlsModule: String, Codable, CaseIterable, Sendable {
    case audio
    case mixer
    case timers

    case tracking
    case alerts
    case overlays
    case combos
    case confidence

    case outputs
    case liveStream

    case timecode
    case appleTVRemote
    case airPlayReceiver

    static let defaultOrder: [ServiceControlsModule] = [
        .combos, .timers, .tracking, .overlays, .audio, .alerts,
        .mixer, .confidence, .outputs, .liveStream, .timecode,
        .appleTVRemote,
        .airPlayReceiver,
    ]

    var title: String {
        switch self {
        case .audio: "Music"
        case .mixer: "Mixer"
        case .timers: "Timers"
        case .tracking: "Service Tracking"
        case .alerts: "Alerts"
        case .overlays: "Overlays"
        case .combos: "Combos"
        case .confidence: "Confidence Monitor"
        case .outputs: "Outputs"
        case .liveStream: "Live Stream"
        case .timecode: "Timecode"
        case .appleTVRemote: "Apple TV"
        case .airPlayReceiver: "AirPlay Receiver"
        }
    }

    var glyph: GlyphKind {
        switch self {
        case .audio: .audio
        case .mixer: .mixer
        case .timers: .timers
        case .tracking: .timers
        case .alerts: .alerts
        case .overlays: .overlays
        case .combos: .combos
        case .confidence: .confidence
        case .outputs: .screens
        case .liveStream: .broadcast
        case .timecode: .timers
        case .appleTVRemote: .screens
        case .airPlayReceiver: .screens
        }
    }
}

extension View {

    @ViewBuilder
    func draggablePayload(_ payload: String?) -> some View {
        if let payload {
            draggable(payload)
        } else {
            self
        }
    }
}

extension EnvironmentValues {

    @Entry var moduleCompact: Bool = true

    @Entry var runOnly: Bool = false
}
