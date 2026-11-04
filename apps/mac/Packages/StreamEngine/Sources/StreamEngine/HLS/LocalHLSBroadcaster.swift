import CoreMedia
import CoreVideo
import Foundation
import Network

public final class LocalHLSBroadcaster: @unchecked Sendable {
    public let video: StreamVideoConfiguration
    public private(set) var url: URL?

    private let server = LocalHLSServer()
    private var encoder: HLSVideoEncoder?
    private var muxTask: Task<Void, Never>?
    private var started = false

    public init(video: StreamVideoConfiguration) {
        self.video = video
    }

    public func start() async throws {
        guard !started else { return }
        try await server.start()
        encoder = try HLSVideoEncoder(video: video, segmentDuration: 2)
        guard let encoder else {
            throw StreamSessionError.transportClosed("Local HLS encoder could not start")
        }
        url = await server.url()
        muxTask = Task { [server] in
            await server.consume(encoder.output)
        }
        started = true
    }

    public func append(_ pixelBuffer: CVPixelBuffer, atHostSeconds hostSeconds: Double) {
        guard started, let sample = Self.sampleBuffer(pixelBuffer, at: hostSeconds) else { return }
        encoder?.encode(sample)
    }

    public func stop() async {
        guard started else { return }
        encoder?.finish()
        await muxTask?.value
        muxTask = nil
        encoder = nil
        started = false
        await server.stop()
        url = nil
    }

    private static func sampleBuffer(
        _ pixelBuffer: CVPixelBuffer, at hostSeconds: Double
    ) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        ) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: hostSeconds, preferredTimescale: 600),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }
}

private actor LocalHLSServer {
    private let listener: NWListener?
    private var playlist = HLSPlaylist()
    private var segments: [String: Data] = [:]
    private var continuation: CheckedContinuation<Void, Error>?
    private var baseURL: URL?

    init() {
        listener = try? NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        guard let listener else {
            throw StreamSessionError.transportClosed("Local HLS listener could not start")
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task {
                    switch state {
                    case .ready:
                        guard let self, let port = listener.port else { return }
                        await self.ready(port: port.rawValue)
                    case .failed(let error):
                        guard let self else { return }
                        await self.failed(error)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handle(connection) }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func url() -> URL? { baseURL?.appendingPathComponent("playlist.m3u8") }

    func consume(_ samples: AsyncStream<CMSampleBuffer>) async {
        let writer = TSWriter(segmentDuration: 2)
        let state = SegmentState()
        var hasFormat = false
        writer.sink = { bytes in state.data.append(bytes) }
        writer.onSegmentCut = { [weak self] duration in
            guard let self else { return }
            let segment = state.take(duration: duration)
            Task { await self.publish(name: segment.name, data: segment.data, duration: segment.duration) }
        }
        for await sample in samples {
            if let format = sample.formatDescription {
                writer.videoFormat = format
                hasFormat = true
            }
            if hasFormat { writer.append(sample) }
        }
        if !state.data.isEmpty {
            let segment = state.take(duration: max(writer.openSegmentSeconds, 1.0 / 30.0))
            publish(name: segment.name, data: segment.data, duration: segment.duration)
        }
    }

    func stop() {
        listener?.cancel()
        segments.removeAll()
        playlist = HLSPlaylist()
        baseURL = nil
    }

    private final class SegmentState: @unchecked Sendable {
        var data = Data()
        private var index = 0

        func take(duration: Double) -> (name: String, data: Data, duration: Double) {
            let segment = (name: "seg-\(index).ts", data: data, duration: duration)
            index += 1
            data = Data()
            return segment
        }
    }

    private func publish(name: String, data: Data, duration: Double) {
        segments[name] = data
        playlist.add(name: name, duration: duration)
        let active = Set(playlist.segments.map(\.name))
        segments = segments.filter { active.contains($0.key) }
    }

    private func ready(port: UInt16) {
        baseURL = URL(string: "http://127.0.0.1:\(port)")
        continuation?.resume()
        continuation = nil
    }

    private func failed(_ error: NWError) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8),
                  let path = request.split(separator: " ").dropFirst().first
            else {
                connection.cancel()
                return
            }
            Task {
                let body = await self.body(for: String(path))
                let contentType = path.hasSuffix(".m3u8")
                    ? "application/vnd.apple.mpegurl" : "video/mp2t"
                let header = "HTTP/1.1 \(body == nil ? "404 Not Found" : "200 OK")\r\n"
                    + "Content-Type: \(contentType)\r\n"
                    + "Content-Length: \(body?.count ?? 0)\r\n"
                    + "Connection: close\r\n\r\n"
                let response = Data(header.utf8) + (body ?? Data())
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func body(for path: String) -> Data? {
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        if clean == "/playlist.m3u8" { return Data(playlist.render().utf8) }
        return segments[String(clean.dropFirst())]
    }
}
