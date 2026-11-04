import Combine
import AppKit
import Foundation
import RenderEngine

@MainActor
final class AirPlayReceiverController: ObservableObject {
    static let shared = AirPlayReceiverController()

    let manager = AirPlayManager()

    @Published private(set) var state: AirPlayState = .idle
    @Published private(set) var isRunning = false
    private var stateSubscription: AnyCancellable?
    var audienceOverlayChanged: ((NSView?) -> Void)?
    private var audienceOverlayView: VideoLayerView?

    init() {
        stateSubscription = manager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
            guard let self else { return }
            self.state = state
            if case .mirroring = state {
                if self.audienceOverlayView == nil {
                    self.audienceOverlayView = VideoLayerView(videoDecoder: manager.videoDecoder)
                }
                self.audienceOverlayChanged?(self.audienceOverlayView)
            } else {
                self.audienceOverlayView = nil
                audienceOverlayChanged?(nil)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        manager.start()
        isRunning = true
    }

    func stop() {
        manager.stop()
        isRunning = false
    }

    func restart() {
        manager.restart()
        isRunning = true
    }
}
