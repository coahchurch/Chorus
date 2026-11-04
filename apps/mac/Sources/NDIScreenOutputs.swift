import Foundation
import Observation

@MainActor
@Observable
final class NDIScreenOutputs {
    static let shared = NDIScreenOutputs()

    private(set) var controllers: [UUID: NDIOutputController] = [:]
    private static let defaultsKey = "ndi.screenBackings"
    private static let lowerThirdScreenKey = "ndi.lowerThird.screenID"
    private static let lowerThirdThemeKey = "ndi.lowerThird.themeID"

    private init() {}

    var lowerThirdScreenID: UUID? {
        UserDefaults.standard.string(forKey: Self.lowerThirdScreenKey)
            .flatMap(UUID.init(uuidString:))
    }

    var lowerThirdThemeID: String? {
        UserDefaults.standard.string(forKey: Self.lowerThirdThemeKey)
    }

    func status(for screenID: UUID) -> NDIOutputController.Status? {
        controllers[screenID]?.status
    }

    func isCarrying(_ screenID: UUID) -> Bool {
        controllers[screenID]?.isActive ?? false
    }

    var anySending: Bool {
        controllers.values.contains(where: \.isActive)
    }

    var anyAttention: Bool {
        controllers.values.contains { controller in
            switch controller.status {
            case .interrupted, .failed: true
            default: false
            }
        }
    }

    var sendingScreens: [(screenID: UUID, sourceName: String)] {
        controllers.compactMap { id, controller in
            if case .sending(let name) = controller.status { return (id, name) }
            return nil
        }
    }

    func enable(screenID: UUID, render: RenderContext) {

        guard let info = render.outputs.sliceInfo(for: screenID),
              let screen = render.outputs.placeholderScreens
                  .first(where: { $0.id == info.screenID })
        else { return }
        disable(screenID: screenID)

        DeckLinkScreenOutputs.shared.disable(screenID: screenID, render: render)
        render.outputs.assignPlaceholderDevice(placeholderID: screenID, displayUUID: nil)
        let controller = NDIOutputController(render: render)
        let label = info.name.map { "\(screen.name) — \($0)" } ?? screen.name

        let placement = render.outputs.placement(forSlice: screenID)
        let receivesAirPlay = render.outputs.role(forScreen: screenID) != .liveStream
        controller.start(
            targetID: screenID.uuidString,
            targetName: label,
            sourceName: label,
            width: placement?.frameWidth ?? info.width,
            height: placement?.frameHeight ?? info.height,
            frameRate: screen.framesPerSecond,
            sourceRect: info.sourceRect == CGRect(x: 0, y: 0, width: 1, height: 1)
                ? nil : info.sourceRect,
            placement: placement?.unitRect,
            externalFrameProvider: receivesAirPlay
                ? { AirPlayReceiverController.shared.manager.videoDecoder.latestPixelBuffer }
                : nil
        )
        controllers[screenID] = controller
        persist()
    }

    func disable(screenID: UUID) {
        controllers[screenID]?.stop()
        controllers[screenID] = nil
        persist()
    }

    func refreshForAirPlay(render: RenderContext) {
        let active = controllers.keys.filter {
            render.outputs.role(forScreen: $0) != .liveStream
        }
        for id in active {
            disable(screenID: id)
            enable(screenID: id, render: render)
        }
    }

    func configureLowerThird(themeID: String, render: RenderContext) throws -> UUID {
        guard !themeID.isEmpty else { throw LowerThirdOutputError.missingTheme }
        let screenID = lowerThirdScreenID ?? UUID()
        if !render.outputs.placeholderScreens.contains(where: { $0.id == screenID }) {
            guard render.outputs.addPlaceholderScreen(
                id: screenID,
                name: "Lower Thirds NDI",
                width: 1920,
                height: 1080,
                framesPerSecond: 30
            ) != nil else {
                throw LowerThirdOutputError.couldNotCreateScreen
            }
        }

        UserDefaults.standard.set(screenID.uuidString, forKey: Self.lowerThirdScreenKey)
        UserDefaults.standard.set(themeID, forKey: Self.lowerThirdThemeKey)
        enable(screenID: screenID, render: render)
        guard controllers[screenID] != nil else { throw LowerThirdOutputError.couldNotStart }
        return screenID
    }

    func disableLowerThird(render: RenderContext) {
        guard let screenID = lowerThirdScreenID else { return }
        disable(screenID: screenID)
        render.outputs.removePlaceholderScreen(id: screenID)
        UserDefaults.standard.removeObject(forKey: Self.lowerThirdScreenKey)
        UserDefaults.standard.removeObject(forKey: Self.lowerThirdThemeKey)
    }

    func restore(render: RenderContext) {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        for raw in stored {
            guard let id = UUID(uuidString: raw) else { continue }
            enable(screenID: id, render: render)
        }
    }

    private func persist() {
        UserDefaults.standard.set(
            controllers.keys.map(\.uuidString).sorted(), forKey: Self.defaultsKey)
    }
}

private enum LowerThirdOutputError: LocalizedError {
    case missingTheme
    case couldNotCreateScreen
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .missingTheme: "Choose a slide theme for the lower-third output."
        case .couldNotCreateScreen: "The dedicated lower-third output could not be created."
        case .couldNotStart: "The dedicated lower-third NDI output could not be started."
        }
    }
}
