import SwiftUI
import AVFoundation
import CoreMedia
import os

struct VideoDisplayView: NSViewRepresentable {
    @ObservedObject var videoDecoder: VideoDecoder

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView(videoDecoder: videoDecoder)
        return view
    }

    func updateNSView(_ nsView: VideoLayerView, context: Context) {
        nsView.videoDecoder = videoDecoder
    }
}

public final class VideoLayerView: NSView {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "VideoDisplay")
    private var displayLayer: AVSampleBufferDisplayLayer!
    var videoDecoder: VideoDecoder {
        didSet {
            startPolling()
        }
    }
    private var frameTimer: Timer?
    private var lastFrameID: ObjectIdentifier?

    public init(videoDecoder: VideoDecoder) {
        self.videoDecoder = videoDecoder
        super.init(frame: .zero)
        setup()
        startPolling()
    }

    public override init(frame frameRect: NSRect) {
        self.videoDecoder = VideoDecoder()
        super.init(frame: frameRect)
        setup()
        startPolling()
    }

    public required init?(coder: NSCoder) {
        self.videoDecoder = VideoDecoder()
        super.init(coder: coder)
        setup()
        startPolling()
    }

    private func startPolling() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            guard let self, let sampleBuffer = self.videoDecoder.latestSampleBuffer else { return }
            let frameID = ObjectIdentifier(sampleBuffer)
            guard frameID != self.lastFrameID else { return }
            self.lastFrameID = frameID
            self.enqueueSampleBuffer(sampleBuffer)
        }
    }

    private func setup() {
        wantsLayer = true

        displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor.black

        layer?.addSublayer(displayLayer)
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            logger.warning("Display layer failed (error=\(String(describing: self.displayLayer.error))), recovering")
            displayLayer.flushAndRemoveImage()
        }

        displayLayer.enqueue(sampleBuffer)
    }

    func flush() {
        displayLayer.flush()
    }
}
